" Vim syntax file
" Application: BeakerLib
" Maintainer: Filip Holec
" Latest Revision: 12 Oct 2015

if exists("b:current_syntax") || (exists("b:current_syntax") && !exists("g:is_sh"))
  finish
endif

runtime! syntax/sh.vim

" Define keywords
syn keyword blJournalKeyword rlJournalStart rlJournalEnd rlJournalPrint rlJournalPrintText nextgroup=syntaxElement2
syn keyword blPhasesKeyword rlPhaseStart rlPhaseEnd rlPhaseStartSetup rlPhaseStartTest rlPhaseStartCleanup
syn keyword blLoggingKeyword rlLog rlLogDebug rlLogInfo rlLogWarning rlLogError rlLogFatal rlDie rlBundleLogs
syn keyword blMainKeyword rlWatchdog rlReport
syn keyword blBackupKeyword rlFileBackup rlFileRestore
syn keyword blAssertKeyword rlAssert0 rlAssertEquals rlAssertNotEquals rlAssertGreater rlAssertGreaterOrEqual rlAssertExists rlAssertNotExists rlAssertGrep rlAssertNotGrep rlAssertDiffer rlAssertNotDiffer
syn keyword blServicesKeyword rlServiceStart rlServiceStop rlServiceRestore
syn keyword blrpmKeyword rlCheckRpm rlAssertRpm rlAssertNotRpm
syn keyword blMountKeyword rlMount rlCheckMount rlAssertMount
syn keyword blInfoKeyword rlShowPackageVersion rlGetArch rlGetDistroRelease rlGetDistroVariant rlShowRunningKernel
syn keyword blMetricKeyword rlLogMetricLow rlLogMetricHigh
syn keyword blTimeKeyword rlPerfTime_RunsInTime rlPerfTime_AvgFromRuns
syn keyword blXserverKeyword rlVirtualXStart rlVirtualXGetDisplay rlVirtualXStop

syn cluster blAll contains=blJournalKeyword,blPhasesKeyword,blLoggingKeyword,blMainKeyword,blBackupKeyword,blAssertKeyword,blServicesKeyword,blrpmKeyword,blMountKeyword,blInfoKeyword,blMetricKeyword,blTimeKeyword,blXserverKeyword

" highlight BeakerLib kewords in loops,if,case and function blocks too
syn cluster shLoopList  add=@blAll,blrlRun
syn cluster shFunctionList add=@blAll,blrlRun
syn cluster shCaseEsacList add=@blAll,blrlRun
syn cluster shCaseList add=@blAll,blrlRun

" highlight Journal block
syn region blJournal matchgroup=blJournalKeyword start=/rlJournalStart/ end=/rlJournalEnd/ transparent

" highlight Phases block
syn region blPhases matchgroup=blPhasesKeyword start=/rlPhaseStart\(Setup\|Test\|Cleanup\)\?/ end=/rlPhaseEnd/ nextgroup=blPhasesType skipwhite transparent
syn match blPhasesType /\(FAIL\|WARN\)/

syn match blrlRun /rlRun/ nextgroup=blrlRunArgs skipwhite
syn match blrlRunArgs /-t\|-l\|-c\|-s\|[^"\\]\+/ nextgroup=blCommandSub skipwhite contained
syn region blCommandSub matchgroup=shCmdSubRegion start=/"/ skip='\\\\\|\\.' end=/"/ contained contains=@shCommandSubList
"syn region blCommandSub matchgroup=shCmdSubRegion start=/"/ skip='\\\\\|\\.' end=/"/ contained transparent




hi def link blCommandSub			Special
hi def link blJournalKeyword		blStatement
"hi def link blJournal				Identifier
hi def link blPhasesKeyword			blStatement
"hi def link blPhases				Type
hi def link blrlRunArgs				blrlRun
hi def link blrlRun					blIdentifier
hi def link blPhasesType			Type
hi def link blLoggingKeyword 		blIdentifier
hi def link blMainKeyword			blIdentifier
hi def link blBackupKeyword			blIdentifier
hi def link blAssertKeyword			blIdentifier
hi def link blServicesKeyword		blIdentifier
hi def link blrpmKeyword 			blIdentifier
hi def link blMountKeyword			blIdentifier
hi def link blInfoKeyword			blIdentifier
hi def link blMetricKeyword			blIdentifier
hi def link blTimeKeyword			blIdentifier
hi def link blXserverKeyword 		blIdentifier
hi def link blIdentifier			Identifier
hi def link blStatement				Statement
