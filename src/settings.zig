pub const Mode = enum {
    compose,
    map,
    translate,

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .compose => "Compose",
            .map => "Map",
            .translate => "Translate",
        };
    }
};

pub const Preset = enum {
    respelling,
    keyman,

    pub fn label(self: Preset) []const u8 {
        return switch (self) {
            .respelling => "Respelling",
            .keyman => "Keyman",
        };
    }
};

pub const Layout = enum {
    mnemonic,
    bom69,

    pub fn label(self: Layout) []const u8 {
        return switch (self) {
            .mnemonic => "Mnemonic",
            .bom69 => "Book of Mormon 1869",
        };
    }
};

pub const Settings = struct {
    preset: Preset = .respelling,
    layout: Layout = .mnemonic,
    /// Spell oi and ew with two letters, as in the 1860s books.
    book_alphabet: bool = false,
    /// Write the AO phoneme with long A. General American merges cot and caught.
    cot_caught_merge: bool = false,
};
