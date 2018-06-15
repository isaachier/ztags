# ztags
ctags implementation for Zig written in Zig

## Vim Tagbar Configuration

Add this to your `.vimrc` (fixing `ctagsbin` accordingly):

```
    let g:tagbar_type_zig = {
        \ 'ctagstype' : 'zig',
        \ 'kinds'     : [
            \ 's:structs',
            \ 'u:unions',
            \ 'e:enums',
            \ 'v:variables',
            \ 'm:members',
            \ 'f:functions'
        \ ],
        \ 'sro' : '.',
        \ 'kind2scope' : {
            \ 'e' : 'enum',
            \ 'u' : 'union',
            \ 's' : 'struct'
        \ },
        \ 'scope2kind' : {
            \ 'enum' : 'e',
            \ 'union' : 'u',
            \ 'struct' : 's'
        \ },
        \ 'ctagsbin'  : 'path/to/ztags',
        \ 'ctagsargs' : ''
    \ }
```
