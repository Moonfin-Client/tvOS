// AudioUnitInterpose.c
// Dolby Atmos causes the RemoteIO AudioUnit to report an unparseable channel
// layout (-10879), which makes mpv's audiounit AO fail to initialize.
// This file rebinds AudioUnitGetPropertyInfo/AudioUnitGetProperty at runtime
// so the failing channel layout query returns a stereo fallback instead.

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudioTypes.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <string.h>
#include <libkern/OSCacheControl.h>

static OSStatus (*orig_AudioUnitGetPropertyInfo)(AudioUnit, AudioUnitPropertyID,
    AudioUnitScope, AudioUnitElement, UInt32 *, Boolean *) = NULL;
static OSStatus (*orig_AudioUnitGetProperty)(AudioUnit, AudioUnitPropertyID,
    AudioUnitScope, AudioUnitElement, void *, UInt32 *) = NULL;

static OSStatus patched_AudioUnitGetPropertyInfo(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    UInt32 *outDataSize,
    Boolean *outWritable)
{
    if (!orig_AudioUnitGetPropertyInfo) return -1;
    OSStatus result = orig_AudioUnitGetPropertyInfo(inUnit, inID, inScope,
                                                     inElement, outDataSize, outWritable);

    if (result != noErr &&
        inID == kAudioUnitProperty_AudioChannelLayout &&
        inScope == kAudioUnitScope_Output &&
        inElement == 0) {
        if (outDataSize) *outDataSize = (UInt32)sizeof(AudioChannelLayout);
        if (outWritable) *outWritable = false;
        return noErr;
    }

    return result;
}

static OSStatus patched_AudioUnitGetProperty(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    void *outData,
    UInt32 *ioDataSize)
{
    if (!orig_AudioUnitGetProperty) return -1;
    OSStatus result = orig_AudioUnitGetProperty(inUnit, inID, inScope,
                                                 inElement, outData, ioDataSize);

    if (result != noErr &&
        inID == kAudioUnitProperty_AudioChannelLayout &&
        inScope == kAudioUnitScope_Output &&
        inElement == 0 &&
        outData != NULL &&
        ioDataSize != NULL &&
        *ioDataSize >= sizeof(AudioChannelLayout)) {
        AudioChannelLayout *layout = (AudioChannelLayout *)outData;
        memset(layout, 0, sizeof(AudioChannelLayout));
        layout->mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
        *ioDataSize = (UInt32)sizeof(AudioChannelLayout);
        return noErr;
    }

    return result;
}

struct rebinding_entry {
    const char *name;
    void *replacement;
    void **original;
};

static void rebind_symbols_for_image(const struct mach_header *header,
                                     intptr_t slide,
                                     struct rebinding_entry *entries,
                                     int entry_count);

static void rebind_in_section(struct rebinding_entry *entries,
                              int entry_count,
                              uint32_t *indirect_symtab,
                              const struct nlist_64 *symtab,
                              const char *strtab,
                              uint32_t section_indirect_offset,
                              uint32_t num_indirect_syms,
                              void **lazy_ptrs);

static struct rebinding_entry *g_entries = NULL;
static int g_entry_count = 0;

static void _image_callback(const struct mach_header *header, intptr_t slide) {
    if (g_entries && g_entry_count > 0) {
        rebind_symbols_for_image(header, slide, g_entries, g_entry_count);
    }
}

static void rebind_symbols_for_image(const struct mach_header *header,
                                     intptr_t slide,
                                     struct rebinding_entry *entries,
                                     int entry_count)
{
    if (header->magic != MH_MAGIC_64) return;

    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;

    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;
    uintptr_t cur = (uintptr_t)header64 + sizeof(struct mach_header_64);

    for (uint32_t i = 0; i < header64->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)lc;
        }
        cur += lc->cmdsize;
    }

    if (!symtab_cmd || !dysymtab_cmd) return;

    uintptr_t linkedit_segment_vmaddr = 0;
    uintptr_t linkedit_segment_fileoff = 0;
    cur = (uintptr_t)header64 + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header64->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment_vmaddr = seg->vmaddr;
                linkedit_segment_fileoff = seg->fileoff;
                break;
            }
        }
        cur += lc->cmdsize;
    }

    uintptr_t linkedit_actual = linkedit_segment_vmaddr - linkedit_segment_fileoff + slide;
    const struct nlist_64 *symtab = (const struct nlist_64 *)(linkedit_actual + symtab_cmd->symoff);
    const char *strtab = (const char *)(linkedit_actual + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_actual + dysymtab_cmd->indirectsymoff);

    cur = (uintptr_t)header64 + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header64->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_DATA) != 0 &&
                strcmp(seg->segname, "__DATA_CONST") != 0) {
                cur += lc->cmdsize;
                continue;
            }
            struct section_64 *sections = (struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++) {
                uint8_t type = sections[j].flags & SECTION_TYPE;
                if (type == S_LAZY_SYMBOL_POINTERS ||
                    type == S_NON_LAZY_SYMBOL_POINTERS) {
                    uint32_t num_indirect = (uint32_t)(sections[j].size / sizeof(void *));
                    void **ptrs = (void **)(sections[j].addr + slide);
                    rebind_in_section(entries, entry_count,
                                      indirect_symtab, symtab, strtab,
                                      sections[j].reserved1, num_indirect, ptrs);
                }
            }
        }
        cur += lc->cmdsize;
    }
}

static void rebind_in_section(struct rebinding_entry *entries,
                              int entry_count,
                              uint32_t *indirect_symtab,
                              const struct nlist_64 *symtab,
                              const char *strtab,
                              uint32_t section_indirect_offset,
                              uint32_t num_indirect_syms,
                              void **lazy_ptrs)
{
    for (uint32_t i = 0; i < num_indirect_syms; i++) {
        uint32_t symtab_index = indirect_symtab[section_indirect_offset + i];
        if (symtab_index == INDIRECT_SYMBOL_ABS ||
            symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        const char *symbol_name = strtab + strtab_offset;
        if (symbol_name[0] != '_') continue;
        const char *clean_name = symbol_name + 1;

        for (int j = 0; j < entry_count; j++) {
            if (strcmp(clean_name, entries[j].name) == 0) {
                if (entries[j].original && *entries[j].original == NULL) {
                    *entries[j].original = lazy_ptrs[i];
                }
                vm_address_t page = (vm_address_t)&lazy_ptrs[i] & ~(vm_address_t)(getpagesize() - 1);
                vm_size_t page_size = (vm_size_t)getpagesize();
                kern_return_t kr = vm_protect(mach_task_self(), page, page_size, 0,
                                              VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
                if (kr == KERN_SUCCESS) {
                    lazy_ptrs[i] = entries[j].replacement;
                    sys_dcache_flush(&lazy_ptrs[i], sizeof(void *));
                }
                break;
            }
        }
    }
}

void installAudioUnitChannelLayoutFix(void) {
    static int installed = 0;
    if (installed) return;
    installed = 1;

    static struct rebinding_entry entries[2];
    entries[0].name = "AudioUnitGetPropertyInfo";
    entries[0].replacement = (void *)patched_AudioUnitGetPropertyInfo;
    entries[0].original = (void **)&orig_AudioUnitGetPropertyInfo;

    entries[1].name = "AudioUnitGetProperty";
    entries[1].replacement = (void *)patched_AudioUnitGetProperty;
    entries[1].original = (void **)&orig_AudioUnitGetProperty;

    g_entries = entries;
    g_entry_count = 2;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        rebind_symbols_for_image(_dyld_get_image_header(i),
                                 _dyld_get_image_vmaddr_slide(i),
                                 entries, 2);
    }

    _dyld_register_func_for_add_image(_image_callback);
}

