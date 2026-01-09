pub const OryxTag = enum(u8) {
    Nop,
    Class, // parent: IbexInt, len: IbexInt, keys: []String
    Object, // class: IbexInt, len: IbexInt, values: []OryxValue
    Array, // len: IbexInt, values: []OryxValue
    Null,
    False,
    True,
    String, // len: IbexInt, str: []u8
    U8, // int types, all big endian
    U16,
    U32,
    U64,
    U128,
    I8,
    I16,
    I32,
    I64,
    I128,
    F64, // floats, also big endian
    F128,
    IbexInt,
    IbexNumber,
};
