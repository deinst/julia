## from base/boot.jl:
#
# immutable UTF8String <: String
#     data::Array{Uint8,1}
# end
#

## basic UTF-8 decoding & iteration ##

const utf8_offset = [
    0x00000000, 0x00003080,
    0x000e2080, 0x03c82080,
    0xfa082080, 0x82082080,
]

const utf8_trailing = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5,
]

is_utf8_start(byte::Uint8) = ((byte&0xc0)!=0x80)

## required core functionality ##

function endof(s::UTF8String)
    d = s.data
    i = length(d)
    i == 0 && return i
    while !is_utf8_start(d[i])
        i -= 1
    end
    i
end
length(s::UTF8String) = int(ccall(:u8_strlen, Csize_t, (Ptr{Uint8},), s.data))

function getindex(s::UTF8String, i::Int)
    # potentially faster version
    # d = s.data
    # a::Uint32 = d[i]
    # if a < 0x80; return char(a); end
    # #if a&0xc0==0x80; return '\ufffd'; end
    # b::Uint32 = a<<6 + d[i+1]
    # if a < 0xe0; return char(b - 0x00003080); end
    # c::Uint32 = b<<6 + d[i+2]
    # if a < 0xf0; return char(c - 0x000e2080); end
    # return char(c<<6 + d[i+3] - 0x03c82080)

    d = s.data
    b = d[i]
    if !is_utf8_start(b)
        j = i-1
        while 0 < j && !is_utf8_start(d[j])
            j -= 1
        end
        if 0 < j && i <= j+utf8_trailing[d[j]+1] <= length(d)
            # b is a continuation byte of a valid UTF-8 character
            error("invalid UTF-8 character index")
        end
        return '\ufffd'
    end
    trailing = utf8_trailing[b+1]
    if length(d) < i + trailing
        return '\ufffd'
    end
    c::Uint32 = 0
    for j = 1:trailing+1
        c <<= 6
        c += d[i]
        i += 1
    end
    c -= utf8_offset[trailing+1]
    char(c)
end

# this is a trick to allow inlining and tuple elision
next(s::UTF8String, i::Int) = (s[i], i+1+utf8_trailing[s.data[i]+1])

function first_utf8_byte(c::Char)
    c < 0x80    ? uint8(c)            :
    c < 0x800   ? uint8((c>>6 )|0xc0) :
    c < 0x10000 ? uint8((c>>12)|0xe0) :
                  uint8((c>>18)|0xf0)
end

## overload methods for efficiency ##

sizeof(s::UTF8String) = sizeof(s.data)

isvalid(s::UTF8String, i::Integer) =
    (1 <= i <= endof(s.data)) && is_utf8_start(s.data[i])

const empty_utf8 = UTF8String(Uint8[])

function getindex(s::UTF8String, r::UnitRange{Int})
    isempty(r) && return empty_utf8
    i, j = first(r), last(r)
    d = s.data
    if !is_utf8_start(d[i])
        i = nextind(s,i)
    end
    if j > endof(s)
        throw(BoundsError())
    end
    j = nextind(s,j)-1
    UTF8String(d[i:j])
end

function search(s::UTF8String, c::Char, i::Integer)
    if c < 0x80 return search(s.data, uint8(c), i) end
    while true
        i = search(s.data, first_utf8_byte(c), i)
        if i==0 || s[i]==c return i end
        i = next(s,i)[2]
    end
end

function rsearch(s::UTF8String, c::Char, i::Integer)
    if c < 0x80 return rsearch(s.data, uint8(c), i) end
    b = first_utf8_byte(c)
    while true
        i = rsearch(s.data, b, i)
        if i==0 || s[i]==c return i end
        i = prevind(s,i)
    end
end

function string(a::ByteString...)
    if length(a) == 1
        return a[1]::UTF8String
    end
    # ^^ at least one must be UTF-8 or the ASCII-only method would get called
    data = Array(Uint8,0)
    for d in a
        append!(data,d.data)
    end
    UTF8String(data)
end

function reverse(s::UTF8String)
    out = similar(s.data)
    if ccall(:u8_reverse, Cint, (Ptr{Uint8}, Ptr{Uint8}, Csize_t),
             out, s.data, length(out)) == 1
        error("invalid UTF-8 data")
    end
    UTF8String(out)
end

## outputing UTF-8 strings ##

print(io::IO, s::UTF8String) = (write(io, s.data);nothing)
write(io::IO, s::UTF8String) = write(io, s.data)

## transcoding to UTF-8 ##

utf8(x) = convert(UTF8String, x)
convert(::Type{UTF8String}, s::UTF8String) = s
convert(::Type{UTF8String}, s::ASCIIString) = UTF8String(s.data)
convert(::Type{UTF8String}, a::Array{Uint8,1}) = is_valid_utf8(a) ? UTF8String(a) : error("invalid UTF-8 sequence")
function convert(::Type{UTF8String}, a::Array{Uint8,1}, invalids_as::String)
    l = length(a)
    idx = 1
    iscopy = false
    while idx <= l
        if is_utf8_start(a[idx])
            nextidx = idx+1+utf8_trailing[a[idx]+1]
            (nextidx <= (l+1)) && (idx = nextidx; continue)
        end
        !iscopy && (a = copy(a); iscopy = true)
        endn = idx
        while endn <= l
            is_utf8_start(a[endn]) && break
            endn += 1
        end
        (endn > idx) && (endn -= 1)
        splice!(a, idx:endn, invalids_as.data)
        l = length(a)
    end
    UTF8String(a)
end
convert(::Type{UTF8String}, s::String) = utf8(bytestring(s))

# The last case is the replacement character 0xfffd (3 bytes)
utf8sizeof(c::Char) = c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : c < 0x110000 ? 4 : 3
