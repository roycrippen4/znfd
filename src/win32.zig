const std = @import("std");
const root = @import("root.zig");

const Error = root.Error;
const FilterItem = root.FilterItem;
const OpenDialogArgs = root.OpenDialogArgs;
const SaveDialogArgs = root.SaveDialogArgs;
const PickFolderArgs = root.PickFolderArgs;
const WindowHandle = root.WindowHandle;

const win = std.os.windows;
const HRESULT = win.HRESULT;
const DWORD = win.DWORD;
const GUID = win.GUID;
const HWND = win.HWND;
const WCHAR = win.WCHAR;

const S_OK: HRESULT = 0;
const E_CANCELLED: HRESULT = @bitCast(@as(u32, 0x800704C7)); // HRESULT_FROM_WIN32(ERROR_CANCELLED)
const E_FILE_NOT_FOUND: HRESULT = @bitCast(@as(u32, 0x80070002));
const E_INVALID_DRIVE: HRESULT = @bitCast(@as(u32, 0x8007000F));
const RPC_E_CHANGED_MODE: HRESULT = @bitCast(@as(u32, 0x80010106));

const COINIT_APARTMENTTHREADED: DWORD = 0x2;
const COINIT_DISABLE_OLE1DDE: DWORD = 0x4;

const FOS_PICKFOLDERS: DWORD = 0x00000020;
const FOS_FORCEFILESYSTEM: DWORD = 0x00000040;
const FOS_ALLOWMULTISELECT: DWORD = 0x00000200;

const SIGDN_FILESYSPATH: DWORD = 0x80058000;
const SIGDN_DESKTOPABSOLUTEPARSING: DWORD = 0x80028000;

const CLSCTX_ALL: DWORD = 0x17;

const CLSID_FileOpenDialog = GUID.parse("{DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}");
const CLSID_FileSaveDialog = GUID.parse("{C0B4E2F3-BA21-4773-8DBA-335EC946EB8B}");
const IID_IFileOpenDialog = GUID.parse("{D57C7288-D4AD-4768-BE02-9D969532D960}");
const IID_IFileSaveDialog = GUID.parse("{84BCCD23-5FDE-4CDB-AEA4-AF64B83D78AB}");
const IID_IShellItem = GUID.parse("{43826D1E-E718-42EE-BC55-A1E261C37BFE}");

const COMDLG_FILTERSPEC = extern struct {
    pszName: [*:0]const WCHAR,
    pszSpec: [*:0]const WCHAR,
};

// Placeholder type for unused vtable slots.
const VTableFn = *const anyopaque;

// --- COM Interface Definitions ---

const IShellItem = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown
        query_interface: VTableFn,
        add_ref: VTableFn,
        release: *const fn (*IShellItem) callconv(.winapi) u32,
        // IShellItem
        bind_to_handler: VTableFn,
        get_parent: VTableFn,
        get_display_name: *const fn (*IShellItem, DWORD, *[*:0]WCHAR) callconv(.winapi) HRESULT,
        get_attributes: VTableFn,
        compare: VTableFn,
    };

    fn release(self: *IShellItem) void {
        _ = self.lpVtbl.release(self);
    }

    fn get_display_name(self: *IShellItem, sigdn: DWORD) ?[*:0]WCHAR {
        var name: [*:0]WCHAR = undefined;
        if (hr_ok(self.lpVtbl.get_display_name(self, sigdn, &name))) return name;
        return null;
    }
};

const IShellItemArray = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown
        query_interface: VTableFn,
        add_ref: VTableFn,
        release: *const fn (*IShellItemArray) callconv(.winapi) u32,
        // IShellItemArray
        bind_to_handler: VTableFn,
        get_property_store: VTableFn,
        get_property_description_list: VTableFn,
        get_attributes: VTableFn,
        get_count: *const fn (*IShellItemArray, *DWORD) callconv(.winapi) HRESULT,
        get_item_at: *const fn (*IShellItemArray, DWORD, **IShellItem) callconv(.winapi) HRESULT,
        enum_items: VTableFn,
    };

    fn release(self: *IShellItemArray) void {
        _ = self.lpVtbl.release(self);
    }

    fn get_count(self: *IShellItemArray) ?DWORD {
        var count: DWORD = 0;
        if (hr_ok(self.lpVtbl.get_count(self, &count))) return count;
        return null;
    }

    fn get_item_at(self: *IShellItemArray, index: DWORD) ?*IShellItem {
        var item: *IShellItem = undefined;
        if (hr_ok(self.lpVtbl.get_item_at(self, index, &item))) return item;
        return null;
    }
};

const IFileOpenDialog = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (0–2)
        query_interface: VTableFn,
        add_ref: VTableFn,
        release: *const fn (*IFileOpenDialog) callconv(.winapi) u32,
        // IModalWindow (3)
        show: *const fn (*IFileOpenDialog, ?HWND) callconv(.winapi) HRESULT,
        // IFileDialog (4–26)
        set_file_types: *const fn (*IFileOpenDialog, c_uint, [*]const COMDLG_FILTERSPEC) callconv(.winapi) HRESULT,
        set_file_type_index: *const fn (*IFileOpenDialog, c_uint) callconv(.winapi) HRESULT,
        get_file_type_index: VTableFn,
        advise: VTableFn,
        unadvise: VTableFn,
        set_options: *const fn (*IFileOpenDialog, DWORD) callconv(.winapi) HRESULT,
        get_options: *const fn (*IFileOpenDialog, *DWORD) callconv(.winapi) HRESULT,
        set_default_folder: *const fn (*IFileOpenDialog, *IShellItem) callconv(.winapi) HRESULT,
        set_folder: VTableFn,
        get_folder: VTableFn,
        get_current_selection: VTableFn,
        set_file_name: VTableFn,
        get_file_name: VTableFn,
        set_title: VTableFn,
        set_ok_button_label: VTableFn,
        set_file_name_label: VTableFn,
        get_result: *const fn (*IFileOpenDialog, **IShellItem) callconv(.winapi) HRESULT,
        add_place: VTableFn,
        set_default_extension: *const fn (*IFileOpenDialog, [*:0]const WCHAR) callconv(.winapi) HRESULT,
        close: VTableFn,
        set_client_guid: VTableFn,
        clear_client_data: VTableFn,
        set_filter: VTableFn,
        // IFileOpenDialog (27–28)
        get_results: *const fn (*IFileOpenDialog, **IShellItemArray) callconv(.winapi) HRESULT,
        get_selected_items: VTableFn,
    };

    fn release(self: *IFileOpenDialog) void {
        _ = self.lpVtbl.release(self);
    }

    fn show(self: *IFileOpenDialog, owner: ?HWND) HRESULT {
        return self.lpVtbl.show(self, owner);
    }

    fn set_file_types(self: *IFileOpenDialog, count: c_uint, specs: [*]const COMDLG_FILTERSPEC) HRESULT {
        return self.lpVtbl.set_file_types(self, count, specs);
    }

    fn set_file_type_index(self: *IFileOpenDialog, index: c_uint) HRESULT {
        return self.lpVtbl.set_file_type_index(self, index);
    }

    fn set_options(self: *IFileOpenDialog, fos: DWORD) HRESULT {
        return self.lpVtbl.set_options(self, fos);
    }

    fn get_options(self: *IFileOpenDialog) ?DWORD {
        var fos: DWORD = 0;
        if (hr_ok(self.lpVtbl.get_options(self, &fos))) return fos;
        return null;
    }

    fn set_default_folder(self: *IFileOpenDialog, item: *IShellItem) HRESULT {
        return self.lpVtbl.set_default_folder(self, item);
    }

    fn set_default_extension(self: *IFileOpenDialog, ext: [*:0]const WCHAR) HRESULT {
        return self.lpVtbl.set_default_extension(self, ext);
    }

    fn get_result(self: *IFileOpenDialog) ?*IShellItem {
        var item: *IShellItem = undefined;
        if (hr_ok(self.lpVtbl.get_result(self, &item))) return item;
        return null;
    }

    fn get_results(self: *IFileOpenDialog) ?*IShellItemArray {
        var items: *IShellItemArray = undefined;
        if (hr_ok(self.lpVtbl.get_results(self, &items))) return items;
        return null;
    }
};

const IFileSaveDialog = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (0–2)
        query_interface: VTableFn,
        add_ref: VTableFn,
        release: *const fn (*IFileSaveDialog) callconv(.winapi) u32,
        // IModalWindow (3)
        show: *const fn (*IFileSaveDialog, ?HWND) callconv(.winapi) HRESULT,
        // IFileDialog (4–26)
        set_file_types: *const fn (*IFileSaveDialog, c_uint, [*]const COMDLG_FILTERSPEC) callconv(.winapi) HRESULT,
        set_file_type_index: *const fn (*IFileSaveDialog, c_uint) callconv(.winapi) HRESULT,
        get_file_type_index: VTableFn,
        advise: VTableFn,
        unadvise: VTableFn,
        set_options: *const fn (*IFileSaveDialog, DWORD) callconv(.winapi) HRESULT,
        get_options: *const fn (*IFileSaveDialog, *DWORD) callconv(.winapi) HRESULT,
        set_default_folder: *const fn (*IFileSaveDialog, *IShellItem) callconv(.winapi) HRESULT,
        set_folder: VTableFn,
        get_folder: VTableFn,
        get_current_selection: VTableFn,
        set_file_name: *const fn (*IFileSaveDialog, [*:0]const WCHAR) callconv(.winapi) HRESULT,
        get_file_name: VTableFn,
        set_title: VTableFn,
        set_ok_button_label: VTableFn,
        set_file_name_label: VTableFn,
        get_result: *const fn (*IFileSaveDialog, **IShellItem) callconv(.winapi) HRESULT,
        add_place: VTableFn,
        set_default_extension: *const fn (*IFileSaveDialog, [*:0]const WCHAR) callconv(.winapi) HRESULT,
        close: VTableFn,
        set_client_guid: VTableFn,
        clear_client_data: VTableFn,
        set_filter: VTableFn,
        // IFileSaveDialog (27–31)
        set_save_as_item: VTableFn,
        set_properties: VTableFn,
        set_collected_properties: VTableFn,
        get_properties: VTableFn,
        apply_properties: VTableFn,
    };

    fn release(self: *IFileSaveDialog) void {
        _ = self.lpVtbl.release(self);
    }

    fn show(self: *IFileSaveDialog, owner: ?HWND) HRESULT {
        return self.lpVtbl.show(self, owner);
    }

    fn set_file_types(self: *IFileSaveDialog, count: c_uint, specs: [*]const COMDLG_FILTERSPEC) HRESULT {
        return self.lpVtbl.set_file_types(self, count, specs);
    }

    fn set_file_type_index(self: *IFileSaveDialog, index: c_uint) HRESULT {
        return self.lpVtbl.set_file_type_index(self, index);
    }

    fn set_options(self: *IFileSaveDialog, fos: DWORD) HRESULT {
        return self.lpVtbl.set_options(self, fos);
    }

    fn get_options(self: *IFileSaveDialog) ?DWORD {
        var fos: DWORD = 0;
        if (hr_ok(self.lpVtbl.get_options(self, &fos))) return fos;
        return null;
    }

    fn set_default_folder(self: *IFileSaveDialog, item: *IShellItem) HRESULT {
        return self.lpVtbl.set_default_folder(self, item);
    }

    fn set_file_name(self: *IFileSaveDialog, name: [*:0]const WCHAR) HRESULT {
        return self.lpVtbl.set_file_name(self, name);
    }

    fn set_default_extension(self: *IFileSaveDialog, ext: [*:0]const WCHAR) HRESULT {
        return self.lpVtbl.set_default_extension(self, ext);
    }

    fn get_result(self: *IFileSaveDialog) ?*IShellItem {
        var item: *IShellItem = undefined;
        if (hr_ok(self.lpVtbl.get_result(self, &item))) return item;
        return null;
    }
};

// --- Windows API Extern Declarations ---

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, co_init: DWORD) callconv(.winapi) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoCreateInstance(clsid: *const GUID, outer: ?*anyopaque, ctx: DWORD, iid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT;
extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.winapi) void;
extern "shell32" fn SHCreateItemFromParsingName(path: [*:0]const WCHAR, bind_ctx: ?*anyopaque, iid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT;

// --- State ---

var needs_uninitialize: bool = false;

// --- Public API ---

pub fn init() Error!void {
    const hr = CoInitializeEx(null, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (hr_ok(hr)) {
        needs_uninitialize = true;
    } else if (hr == RPC_E_CHANGED_MODE) {
        needs_uninitialize = false;
    } else {
        return error.InitFailed;
    }
}

pub fn deinit() void {
    if (needs_uninitialize) CoUninitialize();
}

pub fn open_dialog(allocator: std.mem.Allocator, args: OpenDialogArgs) Error!?[]const u8 {
    const dialog = create_open_dialog() orelse return error.DialogError;
    defer dialog.release();

    try configure_open_dialog(dialog, args.filter_list, args.default_path);
    merge_options(dialog, FOS_FORCEFILESYSTEM);

    const hr = dialog.show(get_owner(args.parent_window));
    if (hr == E_CANCELLED) return null;
    if (!hr_ok(hr)) return error.DialogError;

    const item = dialog.get_result() orelse return error.DialogError;
    defer item.release();
    return get_path_utf8(allocator, item, SIGDN_FILESYSPATH);
}

pub fn open_dialog_multiple(allocator: std.mem.Allocator, args: OpenDialogArgs) Error![]const []const u8 {
    const dialog = create_open_dialog() orelse return error.DialogError;
    defer dialog.release();

    try configure_open_dialog(dialog, args.filter_list, args.default_path);
    merge_options(dialog, FOS_FORCEFILESYSTEM | FOS_ALLOWMULTISELECT);

    const hr = dialog.show(get_owner(args.parent_window));
    if (hr == E_CANCELLED) return &.{};
    if (!hr_ok(hr)) return error.DialogError;

    const items = dialog.get_results() orelse return error.DialogError;
    defer items.release();
    return collect_shell_item_paths(allocator, items, SIGDN_FILESYSPATH);
}

pub fn save_dialog(allocator: std.mem.Allocator, args: SaveDialogArgs) Error!?[]const u8 {
    const dialog = create_save_dialog() orelse return error.DialogError;
    defer dialog.release();

    try configure_save_dialog(dialog, args);
    merge_options_save(dialog, FOS_FORCEFILESYSTEM);

    const hr = dialog.show(get_owner(args.parent_window));
    if (hr == E_CANCELLED) return null;
    if (!hr_ok(hr)) return error.DialogError;

    const item = dialog.get_result() orelse return error.DialogError;
    defer item.release();
    return get_path_utf8(allocator, item, SIGDN_FILESYSPATH);
}

pub fn pick_folder(allocator: std.mem.Allocator, args: PickFolderArgs) Error!?[]const u8 {
    const dialog = create_open_dialog() orelse return error.DialogError;
    defer dialog.release();

    set_default_path(dialog, args.default_path);
    merge_options(dialog, FOS_FORCEFILESYSTEM | FOS_PICKFOLDERS);

    const hr = dialog.show(get_owner(args.parent_window));
    if (hr == E_CANCELLED) return null;
    if (!hr_ok(hr)) return error.DialogError;

    const item = dialog.get_result() orelse return error.DialogError;
    defer item.release();
    return get_path_utf8(allocator, item, SIGDN_DESKTOPABSOLUTEPARSING);
}

pub fn pick_folder_multiple(allocator: std.mem.Allocator, args: PickFolderArgs) Error![]const []const u8 {
    const dialog = create_open_dialog() orelse return error.DialogError;
    defer dialog.release();

    set_default_path(dialog, args.default_path);
    merge_options(dialog, FOS_FORCEFILESYSTEM | FOS_PICKFOLDERS | FOS_ALLOWMULTISELECT);

    const hr = dialog.show(get_owner(args.parent_window));
    if (hr == E_CANCELLED) return &.{};
    if (!hr_ok(hr)) return error.DialogError;

    const items = dialog.get_results() orelse return error.DialogError;
    defer items.release();
    return collect_shell_item_paths(allocator, items, SIGDN_DESKTOPABSOLUTEPARSING);
}

// --- Internal Helpers ---

fn hr_ok(hr: HRESULT) bool {
    return hr >= 0;
}

fn get_owner(parent_window: ?WindowHandle) ?HWND {
    const pw = parent_window orelse return null;
    if (pw.type != .windows) return null;
    return @ptrCast(pw.handle);
}

fn create_open_dialog() ?*IFileOpenDialog {
    var ppv: ?*anyopaque = null;
    if (!hr_ok(CoCreateInstance(&CLSID_FileOpenDialog, null, CLSCTX_ALL, &IID_IFileOpenDialog, &ppv)))
        return null;
    return @ptrCast(@alignCast(ppv));
}

fn create_save_dialog() ?*IFileSaveDialog {
    var ppv: ?*anyopaque = null;
    if (!hr_ok(CoCreateInstance(&CLSID_FileSaveDialog, null, CLSCTX_ALL, &IID_IFileSaveDialog, &ppv)))
        return null;
    return @ptrCast(@alignCast(ppv));
}

/// OR additional FOS_* flags into the dialog's existing options.
fn merge_options(dialog: *IFileOpenDialog, extra: DWORD) void {
    const existing = dialog.get_options() orelse return;
    _ = dialog.set_options(existing | extra);
}

fn merge_options_save(dialog: *IFileSaveDialog, extra: DWORD) void {
    const existing = dialog.get_options() orelse return;
    _ = dialog.set_options(existing | extra);
}

fn configure_open_dialog(dialog: *IFileOpenDialog, filter_list: []const FilterItem, default_path: ?[]const u8) Error!void {
    if (filter_list.len > 0) {
        try set_filters_open(dialog, filter_list);
        set_default_extension_open(dialog, filter_list);
    }
    set_default_path(dialog, default_path);
}

fn configure_save_dialog(dialog: *IFileSaveDialog, args: SaveDialogArgs) Error!void {
    if (args.filter_list.len > 0) {
        try set_filters_save(dialog, args.filter_list);
        set_default_extension_save(dialog, args.filter_list);
    }
    set_default_path_save(dialog, args.default_path);
    set_default_name(dialog, args.default_name);
}

fn set_filters_open(dialog: *IFileOpenDialog, filter_list: []const FilterItem) Error!void {
    const specs = build_filter_specs(filter_list) orelse return error.DialogError;
    defer free_filter_specs(specs);
    _ = dialog.set_file_types(@intCast(specs.len), specs.ptr);
}

fn set_filters_save(dialog: *IFileSaveDialog, filter_list: []const FilterItem) Error!void {
    const specs = build_filter_specs(filter_list) orelse return error.DialogError;
    defer free_filter_specs(specs);
    _ = dialog.set_file_types(@intCast(specs.len), specs.ptr);
}

fn set_default_extension_open(dialog: *IFileOpenDialog, filter_list: []const FilterItem) void {
    const ext = first_extension_wide(filter_list[0].spec) orelse return;
    defer free_wide_z(ext);
    _ = dialog.set_default_extension(ext);
    _ = dialog.set_file_type_index(1);
}

fn set_default_extension_save(dialog: *IFileSaveDialog, filter_list: []const FilterItem) void {
    const ext = first_extension_wide(filter_list[0].spec) orelse return;
    defer free_wide_z(ext);
    _ = dialog.set_default_extension(ext);
    _ = dialog.set_file_type_index(1);
}

fn set_default_path(dialog: *IFileOpenDialog, default_path: ?[]const u8) void {
    const folder = shell_item_from_path(default_path) orelse return;
    defer folder.release();
    _ = dialog.set_default_folder(folder);
}

fn set_default_path_save(dialog: *IFileSaveDialog, default_path: ?[]const u8) void {
    const folder = shell_item_from_path(default_path) orelse return;
    defer folder.release();
    _ = dialog.set_default_folder(folder);
}

fn set_default_name(dialog: *IFileSaveDialog, default_name: ?[]const u8) void {
    const name = default_name orelse return;
    if (name.len == 0) return;
    const wide = utf8_to_wide_z(name) orelse return;
    defer free_wide_z(wide);
    _ = dialog.set_file_name(wide);
}

fn shell_item_from_path(path: ?[]const u8) ?*IShellItem {
    const p = path orelse return null;
    if (p.len == 0) return null;

    const wide = utf8_to_wide_z_normalized(p) orelse return null;
    defer free_wide_z(wide);

    var ppv: ?*anyopaque = null;
    const hr = SHCreateItemFromParsingName(wide, null, &IID_IShellItem, &ppv);
    if (hr == E_FILE_NOT_FOUND or hr == E_INVALID_DRIVE) return null;
    if (!hr_ok(hr)) return null;
    return @ptrCast(@alignCast(ppv));
}

// --- Filter spec construction ---

/// Build COMDLG_FILTERSPEC array from FilterItems.
/// Converts "png,jpg" to "*.png;*.jpg" and appends an "All files (*.*)" entry.
fn build_filter_specs(filter_list: []const FilterItem) ?[]COMDLG_FILTERSPEC {
    const count = filter_list.len;
    const specs = std.heap.page_allocator.alloc(COMDLG_FILTERSPEC, count + 1) catch return null;
    var built: usize = 0;

    for (filter_list) |item| {
        const name_w = utf8_to_wide_z(item.name) orelse {
            free_built_filter_specs(specs, built);
            return null;
        };
        const spec_w = build_spec_pattern(item.spec) orelse {
            free_wide_z(name_w);
            free_built_filter_specs(specs, built);
            return null;
        };
        specs[built] = .{ .pszName = name_w, .pszSpec = spec_w };
        built += 1;
    }

    // Wildcard — comptime string literals, never freed
    specs[count] = .{
        .pszName = std.unicode.utf8ToUtf16LeStringLiteral("All files"),
        .pszSpec = std.unicode.utf8ToUtf16LeStringLiteral("*.*"),
    };

    return specs[0 .. count + 1];
}

/// Convert "png,jpg" → L"*.png;*.jpg"
fn build_spec_pattern(spec: []const u8) ?[*:0]WCHAR {
    var sep_count: usize = 0;
    for (spec) |ch| {
        if (ch == ',') sep_count += 1;
    }

    // Each extension gets "*." prefix (2 chars), commas become ";" (same count).
    const out_len = spec.len + 2 * (sep_count + 1);
    const buf = std.heap.page_allocator.alloc(WCHAR, out_len + 1) catch return null;

    var i: usize = 0;
    var at_start = true;
    for (spec) |ch| {
        if (at_start) {
            buf[i] = '*';
            i += 1;
            buf[i] = '.';
            i += 1;
            at_start = false;
        }
        if (ch == ',') {
            buf[i] = ';';
            i += 1;
            at_start = true;
        } else {
            buf[i] = ch;
            i += 1;
        }
    }
    buf[i] = 0;
    return buf[0..i :0];
}

fn free_filter_specs(specs: []COMDLG_FILTERSPEC) void {
    const static_name = std.unicode.utf8ToUtf16LeStringLiteral("All files");
    const static_spec = std.unicode.utf8ToUtf16LeStringLiteral("*.*");
    for (specs) |spec| {
        if (spec.pszName != static_name) free_wide_z(spec.pszName);
        if (spec.pszSpec != static_spec) free_wide_z(spec.pszSpec);
    }
    std.heap.page_allocator.free(specs);
}

fn free_built_filter_specs(specs: []COMDLG_FILTERSPEC, built: usize) void {
    for (specs[0..built]) |spec| {
        free_wide_z(spec.pszName);
        free_wide_z(spec.pszSpec);
    }
    std.heap.page_allocator.free(specs);
}

/// Get the first extension from a comma-separated spec (e.g. "png" from "png,jpg").
fn first_extension_wide(spec: []const u8) ?[*:0]WCHAR {
    var end: usize = 0;
    while (end < spec.len and spec[end] != ',') : (end += 1) {}
    if (end == 0) return null;
    return utf8_to_wide_z(spec[0..end]);
}

// --- UTF-8 ↔ UTF-16 conversion ---

fn utf8_to_wide_z(utf8: []const u8) ?[*:0]WCHAR {
    const out_len = std.unicode.calcUtf16LeLen(utf8) catch return null;
    const buf = std.heap.page_allocator.alloc(WCHAR, out_len + 1) catch return null;
    const written = std.unicode.utf8ToUtf16Le(buf, utf8) catch {
        std.heap.page_allocator.free(buf);
        return null;
    };
    buf[written] = 0;
    return buf[0..written :0];
}

fn utf8_to_wide_z_normalized(utf8: []const u8) ?[*:0]WCHAR {
    const wide = utf8_to_wide_z(utf8) orelse return null;
    // Normalize forward slashes to backslashes
    var i: usize = 0;
    while (wide[i] != 0) : (i += 1) {
        if (wide[i] == '/') @as([*]WCHAR, @ptrCast(wide))[i] = '\\';
    }
    return wide;
}

fn free_wide_z(ptr: [*:0]const WCHAR) void {
    const len = std.mem.len(ptr);
    std.heap.page_allocator.free(@constCast(@as([*]const WCHAR, ptr)[0 .. len + 1]));
}

fn get_path_utf8(allocator: std.mem.Allocator, item: *IShellItem, sigdn: DWORD) Error!?[]const u8 {
    const wide_path = item.get_display_name(sigdn) orelse return error.DialogError;
    defer CoTaskMemFree(@ptrCast(wide_path));
    return @as(?[]const u8, try wide_to_utf8_alloc(allocator, wide_path));
}

fn wide_to_utf8_alloc(allocator: std.mem.Allocator, wide: [*:0]const WCHAR) Error![]const u8 {
    const len = std.mem.len(wide);
    const slice = wide[0..len];

    // Measure required UTF-8 length
    var size: usize = 0;
    for (slice) |unit| {
        const cp: u21 = unit;
        size += std.unicode.utf8CodepointSequenceLength(cp) catch return error.DialogError;
    }

    const buf = allocator.alloc(u8, size) catch return error.DialogError;
    var pos: usize = 0;
    for (slice) |unit| {
        const cp: u21 = unit;
        const seq_len = std.unicode.utf8Encode(cp, buf[pos..]) catch {
            allocator.free(buf);
            return error.DialogError;
        };
        pos += seq_len;
    }

    return buf[0..pos];
}

fn collect_shell_item_paths(allocator: std.mem.Allocator, items: *IShellItemArray, sigdn: DWORD) Error![]const []const u8 {
    const count = items.get_count() orelse return error.DialogError;
    if (count == 0) return &.{};

    const paths = allocator.alloc([]const u8, count) catch return error.DialogError;
    var i: DWORD = 0;
    while (i < count) : (i += 1) {
        const item = items.get_item_at(i) orelse {
            free_partial_paths(allocator, paths[0..i]);
            return error.DialogError;
        };
        defer item.release();

        paths[i] = (try get_path_utf8(allocator, item, sigdn)) orelse {
            free_partial_paths(allocator, paths[0..i]);
            return error.DialogError;
        };
    }

    return paths;
}

fn free_partial_paths(allocator: std.mem.Allocator, paths: []const []const u8) void {
    for (paths) |p| allocator.free(p);
    allocator.free(paths);
}
