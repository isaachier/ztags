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
        \ 'f:functions',
        \ 'r:errors'
	\ ],
	\ 'sro' : '.',
	\ 'kind2scope' : {
		\ 'e' : 'enum',
		\ 'u' : 'union',
		\ 's' : 'struct',
        \ 'r' : 'error'
	\ },
	\ 'scope2kind' : {
		\ 'enum' : 'e',
		\ 'union' : 'u',
		\ 'struct' : 's',
		\ 'error' : 'r'
	\ },
	\ 'ctagsbin'  : '~/proj/zig/ztags/zig-cache/ztags',
	\ 'ctagsargs' : ''
\ }
```
