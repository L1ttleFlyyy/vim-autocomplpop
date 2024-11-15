"=============================================================================
" Copyright (c) 2007-2009 Takeshi NISHIDA
"
"=============================================================================
" LOAD GUARD {{{1

if !l9#guardScriptLoading(expand('<sfile>:p'), 0, 0, [])
  finish
endif

" }}}1
"=============================================================================
" GLOBAL FUNCTIONS: {{{1

"
function acp#enable()
  call acp#disable()

  augroup AcpGlobalAutoCommand
    autocmd!
    autocmd InsertEnter * unlet! s:posLast s:lastUncompletable
    autocmd InsertEnter * let  s:acpFirstEnt=1
    autocmd InsertLeave * call s:finishPopup(1)
  augroup END

    autocmd AcpGlobalAutoCommand CursorMovedI * nested call s:feedPopup()
endfunction

"
function acp#disable()
  call s:unmapForMappingDriven()
  augroup AcpGlobalAutoCommand
    autocmd!
  augroup END
endfunction

"
function acp#lock()
  let s:lockCount += 1
endfunction

"
function acp#unlock()
  let s:lockCount -= 1
  if s:lockCount < 0
    let s:lockCount = 0
    throw "AutoComplPop: not locked"
  endif
endfunction

"
function acp#meetsForSnipmate(context)
  if g:acp_behaviorSnipmateLength < 0
    return 0
  endif
  let matches = matchlist(a:context, '\(^\|\s\|[\"'']\@<!\<\)\(\u\{' .
        \                            g:acp_behaviorSnipmateLength . ',}\)$')
  return !empty(matches) && !empty(s:getMatchingSnipItems(matches[2]))
endfunction

"
function acp#meetsForKeyword(context)
  if g:acp_behaviorKeywordLength < 0
    return 0
  endif
  let matches = matchlist(a:context, '\(\k\{' . g:acp_behaviorKeywordLength . ',}\)$')
  if empty(matches)
    return 0
  endif
  for ignore in g:acp_behaviorKeywordIgnores
    if stridx(ignore, matches[1]) == 0
      return 0
    endif
  endfor
  return 1
endfunction

"
function acp#meetsForFile(context)
  if g:acp_behaviorFileLength < 0
    return 0
  endif
  if has('win32') || has('win64')
    let separator = '[/\\]'
  else
    let separator = '\/'
  endif
  if a:context !~ '\f' . separator . '\f\{' . g:acp_behaviorFileLength . ',}$'
    return 0
  endif
  return a:context !~ '[*/\\][/\\]\f*$\|[^[:print:]]\f*$'
endfunction

"
function acp#meetsForRubyOmni(context)
  if !has('ruby')
    return 0
  endif
  if g:acp_behaviorRubyOmniMethodLength >= 0 &&
        \ a:context =~ '[^. \t]\(\.\|::\)\k\{' .
        \              g:acp_behaviorRubyOmniMethodLength . ',}$'
    return 1
  endif
  if g:acp_behaviorRubyOmniSymbolLength >= 0 &&
        \ a:context =~ '\(^\|[^:]\):\k\{' .
        \              g:acp_behaviorRubyOmniSymbolLength . ',}$'
    return 1
  endif
  return 0
endfunction

"
function acp#meetsForPythonOmni(context)
  return has('python') && g:acp_behaviorPythonOmniLength >= 0 &&
        \ a:context =~ '\k\.\k\{' . g:acp_behaviorPythonOmniLength . ',}$'
endfunction

"
function acp#meetsForPerlOmni(context)
  return g:acp_behaviorPerlOmniLength >= 0 &&
        \ a:context =~ '\w->\k\{' . g:acp_behaviorPerlOmniLength . ',}$'
endfunction

"
function acp#meetsForPhpOmni(context)
  if g:acp_behaviorPhpOmniLength < 1
    return 0
  endif
  if a:context =~ '[^a-zA-Z0-9_:>\$]$'
    return 0
  endif
  if a:context =~ 'new \k\{' . 
     \            g:acp_behaviorPhpOmniLength . ',}$'
     return 1
  endif
  if a:context =~ '\$\{' . 
     \            g:acp_behaviorPhpOmniLength . ',}$'
     return 1
  endif
  if a:context =~ '[^.]->\%(\h\w*\)\?\|\h\w*::\%(\h\w*\)\?'
     return 1
  endif
  return 0
endfunction

"
function acp#meetsForXmlOmni(context)
  return g:acp_behaviorXmlOmniLength >= 0 &&
        \ a:context =~ '\(<\|<\/\|<[^>]\+ \|<[^>]\+=\"\)\k\{' .
        \              g:acp_behaviorXmlOmniLength . ',}$'
endfunction

"
function acp#meetsForHtmlOmni(context)
    if g:acp_behaviorHtmlOmniLength >= 0
        if a:context =~ '\(<\|<\/\|<[^>]\+ \|<[^>]\+=\"\)\k\{' .g:acp_behaviorHtmlOmniLength . ',}$'
            return 1
        elseif a:context =~ '\(\<\k\{1,}\(=\"\)\{0,1}\|\" \)$'
            let cur = line('.')-1
            while cur > 0
                let lstr = getline(cur)
                if lstr =~ '>[^>]*$'
                    return 0
                elseif lstr =~ '<[^<]*$'
                    return 1
                endif
                let cur = cur-1
            endwhile
            return 0
        endif
    else
        return 0
    endif
endfunction

"
function acp#meetsForCssOmni(context)
  if g:acp_behaviorCssOmniPropertyLength >= 0 &&
        \ a:context =~ '\(^\s\|[;{]\)\s*\k\{' .
        \              g:acp_behaviorCssOmniPropertyLength . ',}$'
    return 1
  endif
  if g:acp_behaviorCssOmniValueLength >= 0 &&
        \ a:context =~ '[:@!]\s*\k\{' .
        \              g:acp_behaviorCssOmniValueLength . ',}$'
    return 1
  endif
  return 0
endfunction

"
function acp#meetsForJavaScriptOmni(context)
    let matches = matchlist(a:context, '\(\k\{1}\)$')
    if empty(matches)
        return 0
    endif
    return 1
endfunction

"
function acp#completeSnipmate(findstart, base)
  if a:findstart
    let s:posSnipmateCompletion = len(matchstr(s:getCurrentText(), '.*\U'))
    return s:posSnipmateCompletion
  endif
  let lenBase = len(a:base)
  let items = snipMate#GetSnippetsForWordBelowCursor(a:base, 0)
  call filter(items, 'strpart(v:val[0], 0, len(a:base)) ==? a:base')
  return map(sort(items), 's:makeSnipmateItem(v:val[0], values(v:val[1])[0])')
endfunction

"
function acp#onPopupCloseSnipmate()
  let word = s:getCurrentText()[s:posSnipmateCompletion :]
  if len(snipMate#GetSnippetsForWordBelowCursor(word, 0))
    call feedkeys("\<C-r>=snipMate#TriggerSnippet()\<CR>", "n")
    return 0
  endif
  return 1
endfunction

"
function acp#onPopupPost()
  " to clear <C-r>= expression on command-line
  echo ''
  if pumvisible() && exists('s:behavsCurrent[s:iBehavs]')
    inoremap <silent> <expr> <C-h> acp#onBs()
    inoremap <silent> <expr> <BS>  acp#onBs()
    if exists('g:AutoComplPopDontSelectFirst') ? g:AutoComplPopDontSelectFirst : 0
      return (s:behavsCurrent[s:iBehavs].command =~# "\<C-p>" ? "\<C-n>"
            \                                                 : "\<C-p>")
    else
      " a command to restore to original text and select the first match
      return (s:behavsCurrent[s:iBehavs].command =~# "\<C-p>" ? "\<C-n>\<Up>"
            \                                                 : "\<C-p>\<Down>")
    endif
  endif
  let s:iBehavs += 1
  if len(s:behavsCurrent) > s:iBehavs 
    call s:setCompletefunc()
    return printf("\<C-e>%s\<C-r>=acp#onPopupPost()\<CR>",
          \       s:behavsCurrent[s:iBehavs].command)
  else
    let s:lastUncompletable = {
          \   'word': s:getCurrentWord(),
          \   'commands': map(copy(s:behavsCurrent), 'v:val.command')[1:],
          \ }
    call s:finishPopup(0)
    return "\<C-e>"
  endif
endfunction

"
function acp#onBs()
  " using "matchstr" and not "strpart" in order to handle multi-byte
  " characters
  if call(s:behavsCurrent[s:iBehavs].meets,
        \ [matchstr(s:getCurrentText(), '.*\ze.')])
    return "\<BS>"
  endif
  return "\<C-e>\<BS>"
endfunction

" }}}1
"=============================================================================
" LOCAL FUNCTIONS: {{{1

"
function s:unmapForMappingDriven()
  if !exists('s:keysMappingDriven')
    return
  endif
  for key in s:keysMappingDriven
    execute 'iunmap ' . key
  endfor
  let s:keysMappingDriven = []
endfunction

"
function s:getCurrentWord()
  return matchstr(s:getCurrentText(), '\k*$')
endfunction

"
function s:getCurrentText()
  return strpart(getline('.'), 0, col('.') - 1)
endfunction

"
function s:getPostText()
  return strpart(getline('.'), col('.') - 1)
endfunction

"
function s:isModifiedSinceLastCall()
  if exists('s:posLast')
    let posPrev = s:posLast
    let nLinesPrev = s:nLinesLast
    let textPrev = s:textLast
  endif
  let s:posLast = getpos('.')
  let s:nLinesLast = line('$')
  let s:textLast = getline('.')
  if !exists('posPrev')
    return 1
  elseif posPrev[1] != s:posLast[1] || nLinesPrev != s:nLinesLast
    return (posPrev[1] - s:posLast[1] == nLinesPrev - s:nLinesLast)
  elseif textPrev ==# s:textLast
    return 0
  elseif posPrev[2] > s:posLast[2]
    return 1
  elseif has('gui_running') && has('multi_byte')
    " NOTE: auto-popup causes a strange behavior when IME/XIM is working
    return posPrev[2] + 1 == s:posLast[2]
  endif
  return posPrev[2] != s:posLast[2]
endfunction

"
function s:makeCurrentBehaviorSet()
  let modified = s:isModifiedSinceLastCall()
  if exists('s:behavsCurrent[s:iBehavs].repeat') && s:behavsCurrent[s:iBehavs].repeat
    let behavs = [ s:behavsCurrent[s:iBehavs] ]
  elseif exists('s:behavsCurrent[s:iBehavs]')
    return []
  elseif modified
    let behavs = copy(exists('g:acp_behavior[&filetype]')
          \           ? g:acp_behavior[&filetype]
          \           : g:acp_behavior['*'])
  else
    return []
  endif
  let text = s:getCurrentText()
  call filter(behavs, 'call(v:val.meets, [text])')
  let s:iBehavs = 0
  if exists('s:lastUncompletable') &&
        \ stridx(s:getCurrentWord(), s:lastUncompletable.word) == 0 &&
        \ map(copy(behavs), 'v:val.command') ==# s:lastUncompletable.commands
    let behavs = []
  else
    unlet! s:lastUncompletable
  endif
  return behavs
endfunction

"
function s:feedPopup()
  if s:acpFirstEnt > 0
      let s:acpFirstEnt = 0
      return ''
  endif
  " NOTE: CursorMovedI is not triggered while the popup menu is visible. And
  "       it will be triggered when popup menu is disappeared.
  if s:lockCount > 0 || pumvisible() || &paste
    return ''
  endif
  if exists('s:behavsCurrent[s:iBehavs].onPopupClose')
    if !call(s:behavsCurrent[s:iBehavs].onPopupClose, [])
      call s:finishPopup(1)
      return ''
    endif
  endif
  let s:behavsCurrent = s:makeCurrentBehaviorSet()
  if empty(s:behavsCurrent)
    call s:finishPopup(1)
    return ''
  endif
  " In case of dividing words by symbols (e.g. "for(int", "ab==cd") while a
  " popup menu is visible, another popup is not available unless input <C-e>
  " or try popup once. So first completion is duplicated.
  call insert(s:behavsCurrent, s:behavsCurrent[s:iBehavs])
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&spell', 0)
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&completeopt', 'menuone' . (g:acp_completeoptPreview ? ',preview' : ''))
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&complete', g:acp_completeOption)
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&ignorecase', g:acp_ignorecaseOption)
  " NOTE: With CursorMovedI driven, Set 'lazyredraw' to avoid flickering.
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&lazyredraw', 1)
  " NOTE: 'textwidth' must be restored after <C-e>.
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP1,
        \ '&textwidth', 0)
  call s:setCompletefunc()
  call feedkeys(s:behavsCurrent[s:iBehavs].command . "\<C-r>=acp#onPopupPost()\<CR>", 'n')
  return '' " this function is called by <C-r>=
endfunction

"
function s:finishPopup(fGroup1)
  inoremap <C-h> <Nop> | iunmap <C-h>
  inoremap <BS>  <Nop> | iunmap <BS>
  let s:behavsCurrent = []
  call l9#tempvariables#end(s:TEMP_VARIABLES_GROUP0)
  if a:fGroup1
    call l9#tempvariables#end(s:TEMP_VARIABLES_GROUP1)
  endif
endfunction

"
function s:setCompletefunc()
  if exists('s:behavsCurrent[s:iBehavs].completefunc')
    call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
          \ '&completefunc', s:behavsCurrent[s:iBehavs].completefunc)
  endif
endfunction

"
function s:makeSnipmateItem(key, snip)
  if type(a:snip) == type([])
    let descriptions = a:snip[0]
    let snipFormatted = descriptions
  elseif type(a:snip) == type({})
    let descriptions = values(a:snip)[0][0]
    let snipFormatted = substitute(descriptions, '\(\n\|\s\)\+', ' ', 'g')
  else
    let snipFormatted = substitute(a:snip, '\(\n\|\s\)\+', ' ', 'g')
  endif
  return  {
        \   'word': a:key,
        \   'menu': strpart(snipFormatted, 0, 80),
        \ }
endfunction

"
function s:getMatchingSnipItems(base)
  let key = a:base . "\n"
  if !exists('s:snipItems[key]')
    let s:snipItems[key] = snipMate#GetSnippetsForWordBelowCursor(tolower(a:base), 0)
    call filter(s:snipItems[key], 'strpart(v:val[0], 0, len(a:base)) ==? a:base')
    call map(s:snipItems[key], 's:makeSnipmateItem(v:val[0], v:val[1])')
  endif
  return s:snipItems[key]
endfunction

" }}}1
"=============================================================================
" INITIALIZATION {{{1

let s:TEMP_VARIABLES_GROUP0 = "AutoComplPop0"
let s:TEMP_VARIABLES_GROUP1 = "AutoComplPop1"
let s:lockCount = 0
let s:behavsCurrent = []
let s:iBehavs = 0
let s:snipItems = {}
let s:acpFirstEnt = 0

" }}}1
"=============================================================================
" vim: set fdm=marker:
