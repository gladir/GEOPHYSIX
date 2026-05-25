{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)

  SAC.PAS - Clone console compact de Seismic Analysis Code.

  Ce programme fournit un interpreteur SAC autonome en Pascal. Il reconnait
  les commandes SAC historiques, implemente un noyau utile de lecture,
  ecriture et traitement de traces, et conserve des points d'extension
  explicites pour les commandes graphiques, bases de donnees et modules
  avances du SAC original.

  Phases internes:
   1. Noyau de donnees: traces, en-tetes SAC simplifiees, fichiers.
   2. Moteur: analyse de lignes, macros, variables BB, historique.
   3. Commandes: traitements numeriques, I/O, affichage texte, stubs SAC.
}

Program SAC;

{$E+,N+}

Uses
 Dos;

Const
 MaxTraces  = 8;
 MaxSamples = 4096;
 MaxTokens  = 32;
 MaxBB      = 64;
 MaxHist    = 128;
 SACHeaderBytes = 632;
 PiValue = 3.1415926535897932385;

Type
 TSampleArray = Array[1..MaxSamples] Of Single;
 PSampleArray = ^TSampleArray;
 TTrace = Record
  Used:Boolean;
  FileName:String;
  Npts:LongInt;
  Delta,B,E,O,A:Single;
  Kstnm,Kcmpnm:String[8];
  Data:TSampleArray;
  FftRe,FftIm:PSampleArray;
  FftN:LongInt;
  FftDelta:Single;
 End;
 PTrace = ^TTrace;
 PTraceNode = ^TTraceNode;
 TTraceNode = Record
  Trace:TTrace;
  Next:PTraceNode;
 End;
 TTokens = Array[1..MaxTokens] Of String;
 TBBVar = Record
  Name,Value:String;
 End;
 PHistNode = ^THistNode;
 THistNode = Record
  Line:String;
  Next:PHistNode;
 End;

Var
 Traces,Saved:PTraceNode;
 BB:Array[1..MaxBB] Of TBBVar;
 HistFirst,HistLast:PHistNode;
 BBCount,HistCount:Integer;
 Running,InSub:Boolean;
 CutOn:Boolean;
 CutB,CutE:Single;
 ReadErrMode,CutErrMode:String;
 TranscriptOn:Boolean;
 TranscriptFile:Text;

Function UpCaseStr(S:String):String;
Var I:Integer;
Begin
 For I:=1 To Length(S) Do S[I]:=UpCase(S[I]);
 UpCaseStr:=S;
End;

Function TrimStr(S:String):String;
Begin
 While (Length(S)>0) And (S[1]<=' ') Do Delete(S,1,1);
 While (Length(S)>0) And (S[Length(S)]<=' ') Do Delete(S,Length(S),1);
 TrimStr:=S;
End;

Function FileExt(S:String):String;
Var I:Integer; E:String;
Begin
 E:='';
 For I:=Length(S) Downto 1 Do Begin
  If S[I]='.' Then Begin E:=Copy(S,I,Length(S)-I+1); Break; End;
  If (S[I]='\') Or (S[I]='/') Or (S[I]=':') Then Break;
 End;
 FileExt:=UpCaseStr(E);
End;

Function Tokenize(Line:String; Var T:TTokens):Integer;
Var I,N:Integer; Q:Boolean; Cur:String; C:Char;
Begin
 For I:=1 To MaxTokens Do T[I]:='';
 N:=0; Cur:=''; Q:=False;
 For I:=1 To Length(Line) Do Begin
  C:=Line[I];
  If C='"' Then Q:=Not Q
   Else If (C<=' ') And Not Q Then Begin
    If Cur<>'' Then Begin
     Inc(N);
     If N<=MaxTokens Then T[N]:=Cur;
     Cur:='';
    End;
   End
   Else Cur:=Cur+C;
 End;
 If Cur<>'' Then Begin
  Inc(N);
  If N<=MaxTokens Then T[N]:=Cur;
 End;
 Tokenize:=N;
End;

Function ToReal(S:String; Def:Single):Single;
Var R:Real; Code:Integer;
Begin
 Val(S,R,Code);
 If Code=0 Then ToReal:=R Else ToReal:=Def;
End;

Function ToInt(S:String; Def:LongInt):LongInt;
Var L:LongInt; Code:Integer;
Begin
 Val(S,L,Code);
 If Code=0 Then ToInt:=L Else ToInt:=Def;
End;

Function TicksNow:LongInt;
Var H,M,S,HS:Word;
Begin
 GetTime(H,M,S,HS);
 TicksNow:=(((LongInt(H)*60+M)*60)+S)*100+HS;
End;

Procedure WaitMs(MS:LongInt);
Var Start,NowT,Need:LongInt;
Begin
 If MS<=0 Then Exit;
 Need:=MS Div 10; If Need<1 Then Need:=1;
 Start:=TicksNow;
 Repeat
  NowT:=TicksNow;
  If NowT<Start Then NowT:=NowT+24*60*60*100;
 Until (NowT-Start)>=Need;
End;

Procedure Say(S:String);
Begin
 WriteLn(S);
 If TranscriptOn Then WriteLn(TranscriptFile,S);
End;

Procedure AddHistory(S:String);
Var P,Old:PHistNode;
Begin
 New(P); P^.Line:=S; P^.Next:=Nil;
 If HistFirst=Nil Then HistFirst:=P Else HistLast^.Next:=P;
 HistLast:=P;
 If HistCount<MaxHist Then Inc(HistCount)
  Else Begin
   Old:=HistFirst;
   HistFirst:=HistFirst^.Next;
   If HistFirst=Nil Then HistLast:=Nil;
   Dispose(Old);
  End;
End;

Procedure ShowHistory;
Var P:PHistNode; I:Integer;
Begin
 P:=HistFirst; I:=1;
 While P<>Nil Do Begin
  WriteLn(I:3,' ',P^.Line);
  P:=P^.Next; Inc(I);
 End;
End;

Procedure InitTrace(Var Tr:TTrace);
Var I:Integer;
Begin
 If Tr.FftRe<>Nil Then Begin Dispose(Tr.FftRe); Tr.FftRe:=Nil; End;
 If Tr.FftIm<>Nil Then Begin Dispose(Tr.FftIm); Tr.FftIm:=Nil; End;
 Tr.Used:=False; Tr.FileName:='';
 Tr.Npts:=0; Tr.Delta:=1.0; Tr.B:=0.0; Tr.E:=0.0; Tr.O:=0.0; Tr.A:=-12345.0;
 Tr.Kstnm:='-12345'; Tr.Kcmpnm:='-12345';
 Tr.FftN:=0; Tr.FftDelta:=1.0;
 For I:=1 To MaxSamples Do Tr.Data[I]:=0.0;
End;

Function TraceAt(Head:PTraceNode; Index:Integer):PTrace;
Var P:PTraceNode; I:Integer;
Begin
 P:=Head; I:=1;
 While (P<>Nil) And (I<Index) Do Begin P:=P^.Next; Inc(I); End;
 If P=Nil Then TraceAt:=Nil Else TraceAt:=Addr(P^.Trace);
End;

Function TracePtr(Index:Integer):PTrace;
Begin
 TracePtr:=TraceAt(Traces,Index);
End;

Function SavedPtr(Index:Integer):PTrace;
Begin
 SavedPtr:=TraceAt(Saved,Index);
End;

Procedure CreateTraceList(Var Head:PTraceNode);
Var I:Integer; P,Q:PTraceNode;
Begin
 Head:=Nil; Q:=Nil;
 For I:=1 To MaxTraces Do Begin
  New(P); P^.Trace.FftRe:=Nil; P^.Trace.FftIm:=Nil; InitTrace(P^.Trace); P^.Next:=Nil;
  If Head=Nil Then Head:=P Else Q^.Next:=P;
  Q:=P;
 End;
End;

Procedure CopyTrace(Var Dest:TTrace; Var Src:TTrace);
Var I:Integer;
Begin
 If Dest.FftRe<>Nil Then Begin Dispose(Dest.FftRe); Dest.FftRe:=Nil; End;
 If Dest.FftIm<>Nil Then Begin Dispose(Dest.FftIm); Dest.FftIm:=Nil; End;
 Dest.Used:=Src.Used; Dest.FileName:=Src.FileName; Dest.Npts:=Src.Npts;
 Dest.Delta:=Src.Delta; Dest.B:=Src.B; Dest.E:=Src.E; Dest.O:=Src.O; Dest.A:=Src.A;
 Dest.Kstnm:=Src.Kstnm; Dest.Kcmpnm:=Src.Kcmpnm;
 Dest.FftN:=Src.FftN; Dest.FftDelta:=Src.FftDelta;
 For I:=1 To MaxSamples Do Dest.Data[I]:=Src.Data[I];
 If Src.FftRe<>Nil Then Begin
  New(Dest.FftRe);
  For I:=1 To MaxSamples Do Dest.FftRe^[I]:=Src.FftRe^[I];
 End;
 If Src.FftIm<>Nil Then Begin
  New(Dest.FftIm);
  For I:=1 To MaxSamples Do Dest.FftIm^[I]:=Src.FftIm^[I];
 End;
End;

Procedure UpdateEndTime(Var Tr:TTrace);
Begin
 If Tr.Npts>0 Then Tr.E:=Tr.B+(Tr.Npts-1)*Tr.Delta Else Tr.E:=Tr.B;
End;

Procedure UpdateStats(Var Tr:TTrace; Var DepMin,DepMax,DepMen:Single);
Var I:LongInt; Sum:Real;
Begin
 If Tr.Npts<=0 Then Begin DepMin:=0; DepMax:=0; DepMen:=0; Exit; End;
 DepMin:=Tr.Data[1]; DepMax:=Tr.Data[1]; Sum:=0;
 For I:=1 To Tr.Npts Do Begin
  If Tr.Data[I]<DepMin Then DepMin:=Tr.Data[I];
  If Tr.Data[I]>DepMax Then DepMax:=Tr.Data[I];
  Sum:=Sum+Tr.Data[I];
 End;
 DepMen:=Sum/Tr.Npts;
End;

Function FirstFreeTrace:Integer;
Var I:Integer; P:PTrace;
Begin
 FirstFreeTrace:=0;
 For I:=1 To MaxTraces Do Begin
  P:=TracePtr(I);
  If (P<>Nil) And Not P^.Used Then Begin FirstFreeTrace:=I; Exit; End;
 End;
End;

Function TraceCount:Integer;
Var I,N:Integer; P:PTrace;
Begin
 N:=0;
 For I:=1 To MaxTraces Do Begin
  P:=TracePtr(I);
  If (P<>Nil) And P^.Used Then Inc(N);
 End;
 TraceCount:=N;
End;

Procedure ClearTraces;
Var I:Integer; P:PTrace;
Begin
 For I:=1 To MaxTraces Do Begin
  P:=TracePtr(I);
  If P<>Nil Then InitTrace(P^);
 End;
End;

Procedure CommitTraces;
Var I:Integer; P,S:PTrace;
Begin
 For I:=1 To MaxTraces Do Begin
  P:=TracePtr(I); S:=SavedPtr(I);
  If (P<>Nil) And (S<>Nil) Then CopyTrace(S^,P^);
 End;
 Say('Trace state committed.');
End;

Procedure RollbackTraces;
Var I:Integer; P,S:PTrace;
Begin
 For I:=1 To MaxTraces Do Begin
  P:=TracePtr(I); S:=SavedPtr(I);
  If (P<>Nil) And (S<>Nil) Then CopyTrace(P^,S^);
 End;
 Say('Trace state restored.');
End;

Function BBIndex(Name:String):Integer;
Var I:Integer;
Begin
 Name:=UpCaseStr(Name);
 BBIndex:=0;
 For I:=1 To BBCount Do If UpCaseStr(BB[I].Name)=Name Then Begin BBIndex:=I; Exit; End;
End;

Procedure SetBBVar(Name,Value:String);
Var I:Integer;
Begin
 I:=BBIndex(Name);
 If I=0 Then Begin
  If BBCount>=MaxBB Then Begin Say('BB table full.'); Exit; End;
  Inc(BBCount); I:=BBCount; BB[I].Name:=UpCaseStr(Name);
 End;
 BB[I].Value:=Value;
End;

Function GetBBVar(Name:String):String;
Var I:Integer;
Begin
 I:=BBIndex(Name);
 If I=0 Then GetBBVar:='' Else GetBBVar:=BB[I].Value;
End;

Procedure UnsetBBVar(Name:String);
Var I:Integer;
Begin
 I:=BBIndex(Name);
 If I>0 Then Begin
  While I<BBCount Do Begin BB[I]:=BB[I+1]; Inc(I); End;
  Dec(BBCount);
 End;
End;

Procedure SubstituteBB(Var Line:String);
Var I,P:Integer; Key,Valu:String;
Begin
 For I:=1 To BBCount Do Begin
  Key:='%'+UpCaseStr(BB[I].Name)+'%';
  Repeat
   P:=Pos(Key,UpCaseStr(Line));
   If P>0 Then Begin
    Valu:=BB[I].Value;
    Delete(Line,P,Length(Key));
    Insert(Valu,Line,P);
   End;
  Until P=0;
 End;
End;

Function IsCommandKnown(Cmd:String):Boolean;
Const
 Command:Array[0..241] Of String[20]=(
  '3C','ABOUT','ABS','ADD','ADDF','APK',
  'ARRAYMAP','AXES','BANDPASS','BANDREJ','BBFK','BEAM',
  'BEGINDEVICES','BEGINFRAME','BEGINWINDOW','BENIOFF','BINOPERR','BORDER',
  'CAPF','CHNHDR','CHPF','COLOR','COMCOR','CONTOUR',
  'CONVERT','CONVOLVE','COPYHDR','CORRELATE','COMMIT','RECALLTRACE',
  'ROLLBACK','CUT','CUTERR','CUTIM','DATAGEN','DECIMATE',
  'DELETECHANNEL','DIF','DIV','DIVF','DIVOMEGA','ECHO',
  'ENDDEVICES','ENDFRAME','ENVELOPE','ERASE','EVALUATE','EXP',
  'EXP10','FFT','FILEID','FILENUMBER','FG','FILTERDESIGN',
  'FIR','FLOOR','FUNCGEN','GETBB','GRAYSCALE','GRID',
  'GTEXT','HANNING','HELP','HIGHPASS','HILBERT','HISTORY',
  'IFFT','IMAGE','INICM','INSTALLMACRO','INT','INTERPOLATE',
  'KEEPAM','KHRONHITE','LINE','LINEFIT','LINLIN','LINLOG',
  'LISTHDR','LOAD','LOADCTABLE','LOG','LOG10','LOGLAB',
  'LOGLIN','LOGLOG','LOWPASS','MACRO','MAP','MARKPTP',
  'MARKTIMES','MARKVALUE','MAT','MATHOP','MERGE','MESSAGE',
  'MTW','MUL','MULF','MULOMEGA','PLOTC','NULL',
  'OAPF','OHPF','PAUSE','PICKAUTHOR','PICKPHASE','PICKPREFS',
  'PICKS','PLABEL','PLOT','PLOT1','PLOT2','PLOTALPHA',
  'PLOTCTABLE','PLOTDY','PLOTPK','PLOTPKTABLE','PLOTPM','PLOTSP',
  'PLOTXY','PRINT','PRINTHELP','PRODUCTION','QDP','QUANTIZE',
  'QUIT','QUITSUB','READ','READBBF','READCSS','READDB',
  'READERR','READGSE','READHDR','READSDD','READSP','READSUDS',
  'READTABLE','REPORT','REVERSE','RGLITCHES','RMEAN','RMS',
  'ROTATE','RQ','RTREND','SAVEIMG','SCALLOP','SETBB',
  'SETDEVICE','SETMACRO','SGF','SMOOTH','SONOGRAM','SORT',
  'SPECTROGRAM','SQR','SQRT','STRETCH','SUB','SUBF',
  'SYMBOL','SYNCHRONIZE','SYSTEMCOMMAND','TAPER','TICKS','TITLE',
  'TRACE','TRANSCRIPT','TRANSFER','TRAVELTIME','TSIZE','UNSETBB',
  'UNWRAP','VSPACE','WAIT','WHITEN','WHPF','WIDTH',
  'WIENER','WILD','WINDOW','WRITE','WRITEBBF','WRITECSS',
  'WRITEGSE','WRITEHDR','WRITESDD','WRITESP','XDIV','XFUDGE',
  'XFULL','XGRID','XLABEL','XLIM','XLIN','XLOG',
  'XVPORT','YDIV','YFUDGE','YFULL','YGRID','YLABEL',
  'YLIM','YLIN','YLOG','YVPORT','ZCOLORS','ZLABELS',
  'ZLEVELS','ZLINES','ZTICKS','ADDSTACK','CHANGESTACK','DELETESTACK',
  'DELTACHECK','DISTANCEAXIS','DISTANCEWINDOW','GLOBALSTACK','INCREMENTSTACK','LISTSTACK',
  'PLOTRECORDSECTION','PLOTSTACK','SUMSTACK','TIMEAXIS','TIMEWINDOW','SSSTRAVELTIME',
  'VELOCITYMODEL','VELOCITYROSET','WRITESTACK','ZEROSTACK','COR','MEM',
  'MLM','PDS','PLOTCOR','PLOTPE','PLOTSPE','READCOR',
  'WRITECOR','WRITESPE');
Var I:Integer;
Begin
 Cmd:=UpCaseStr(Cmd);
 IsCommandKnown:=False;
 For I:=0 To High(Command) Do
  If Cmd=Command[I] Then Begin
   IsCommandKnown:=True;
   Exit;
  End;
End;

Procedure WriteCommandList;
Begin
 Say('Commandes SAC reconnues:');
 Say('3C ABOUT ABS ADD ADDF APK ARRAYMAP AXES BANDPASS BANDREJ BBFK BEAM');
 Say('BEGINDEVICES BEGINFRAME BEGINWINDOW BENIOFF BINOPERR BORDER CAPF CHNHDR CHPF');
 Say('COLOR COMCOR CONTOUR CONVERT CONVOLVE COPYHDR CORRELATE COMMIT RECALLTRACE ROLLBACK');
 Say('CUT CUTERR CUTIM DATAGEN DECIMATE DELETECHANNEL DIF DIV DIVF DIVOMEGA ECHO');
 Say('ENDDEVICES ENDFRAME ENVELOPE ERASE EVALUATE EXP EXP10 FFT FILEID FILENUMBER');
 Say('FG FILTERDESIGN FIR FLOOR FUNCGEN GETBB GRAYSCALE GRID GTEXT HANNING HELP HIGHPASS');
 Say('HILBERT HISTORY IFFT IMAGE INICM INSTALLMACRO INT INTERPOLATE KEEPAM KHRONHITE');
 Say('LINE LINEFIT LINLIN LINLOG LISTHDR LOAD LOADCTABLE LOG LOG10 LOGLAB LOGLIN LOGLOG');
 Say('LOWPASS MACRO MAP MARKPTP MARKTIMES MARKVALUE MAT MATHOP MERGE MESSAGE MTW MUL');
 Say('MULF MULOMEGA NULL OAPF OHPF PAUSE PICKAUTHOR PICKPHASE PICKPREFS PICKS PLABEL');
 Say('PLOT PLOT1 PLOT2 PLOTALPHA PLOTC PLOTCTABLE PLOTDY PLOTPK PLOTPKTABLE PLOTPM');
 Say('PLOTSP PLOTXY PRINT PRINTHELP PRODUCTION QDP QUANTIZE QUIT QUITSUB READ READBBF');
 Say('READCSS READDB READERR READGSE READHDR READSDD READSP READSUDS READTABLE REPORT');
 Say('REVERSE RGLITCHES RMEAN RMS ROTATE RQ RTREND SAVEIMG SCALLOP SETBB SETDEVICE');
 Say('SETMACRO SGF SMOOTH SONOGRAM SORT SPECTROGRAM SQR SQRT STRETCH SUB SUBF SYMBOL');
 Say('SYNCHRONIZE SYSTEMCOMMAND TAPER TICKS TITLE TRACE TRANSCRIPT TRANSFER TRAVELTIME');
 Say('TSIZE UNSETBB UNWRAP VSPACE WAIT WHITEN WHPF WIDTH WIENER WILD WINDOW WRITE');
 Say('WRITEBBF WRITECSS WRITEGSE WRITEHDR WRITESDD WRITESP X*/Y*/Z* graph commands');
 Say('Subprocess: ADDSTACK ... ZEROSTACK, COR MEM MLM PDS ... WRITESPE');
End;

Procedure Unsupported(Cmd:String);
Begin
 Say('SAC: '+Cmd+' est reconnue; implementation complete non incluse dans ce clone console.');
End;

Procedure ReadSacBinary(FileName:String);
Type TFloatHeader = Array[0..69] Of Single;
     TIntHeader = Array[0..39] Of LongInt;
Var F:File; Floats:TFloatHeader; Ints:TIntHeader; Buf:Array[1..192] Of Byte;
    Got,Idx:Integer; N,I:LongInt; Code:Integer;
    Tr:PTrace;
Begin
 Idx:=FirstFreeTrace;
 If Idx=0 Then Begin Say('No free trace slots.'); Exit; End;
 Tr:=TracePtr(Idx);
 If Tr=Nil Then Exit;
 Assign(F,FileName); {$I-} Reset(F,1); {$I+}
 Code:=IOResult;
 If Code<>0 Then Begin
  If ReadErrMode='FATAL' Then Begin Say('Cannot open '+FileName); Running:=False; End
   Else Say('Cannot open '+FileName);
  Exit;
 End;
 BlockRead(F,Floats,SizeOf(Floats),Got);
 If Got<>SizeOf(Floats) Then Begin Close(F); Say('Short SAC float header.'); Exit; End;
 BlockRead(F,Ints,SizeOf(Ints),Got);
 If Got<>SizeOf(Ints) Then Begin Close(F); Say('Short SAC integer header.'); Exit; End;
 BlockRead(F,Buf,SizeOf(Buf),Got);
 N:=Ints[9];
 If N<0 Then N:=0;
 If N>MaxSamples Then Begin Say('Trace truncated to internal MaxSamples.'); N:=MaxSamples; End;
 InitTrace(Tr^); Tr^.Used:=True; Tr^.FileName:=FileName;
 Tr^.Delta:=Floats[0]; Tr^.B:=Floats[5]; Tr^.E:=Floats[6];
 Tr^.O:=Floats[7]; Tr^.A:=Floats[8]; Tr^.Npts:=N;
 For I:=1 To N Do Begin
  BlockRead(F,Tr^.Data[I],SizeOf(Single),Got);
  If Got<>SizeOf(Single) Then Begin Tr^.Npts:=I-1; Break; End;
 End;
 Close(F);
 UpdateEndTime(Tr^);
 Say('Read '+FileName+' into trace '+Chr(Ord('0')+Idx)+'.');
End;

Procedure ReadAscii(FileName:String);
Var F:Text; S:String; V:Single; Code:Integer; Idx:Integer; N:LongInt;
    Tr:PTrace;
Begin
 Idx:=FirstFreeTrace;
 If Idx=0 Then Begin Say('No free trace slots.'); Exit; End;
 Tr:=TracePtr(Idx);
 If Tr=Nil Then Exit;
 Assign(F,FileName); {$I-} Reset(F); {$I+}
 Code:=IOResult;
 If Code<>0 Then Begin Say('Cannot open '+FileName); Exit; End;
 InitTrace(Tr^); Tr^.Used:=True; Tr^.FileName:=FileName; N:=0;
 While Not Eof(F) And (N<MaxSamples) Do Begin
  ReadLn(F,S); S:=TrimStr(S);
  If S<>'' Then Begin
   V:=ToReal(S,0.0); Inc(N); Tr^.Data[N]:=V;
  End;
 End;
 Close(F);
 Tr^.Npts:=N; UpdateEndTime(Tr^);
 Say('Read ASCII '+FileName+' into trace '+Chr(Ord('0')+Idx)+'.');
End;

Procedure WriteSacBinary(FileName:String; Idx:Integer);
Type TFloatHeader = Array[0..69] Of Single;
     TIntHeader = Array[0..39] Of LongInt;
Var F:File; Floats:TFloatHeader; Ints:TIntHeader; Buf:Array[1..192] Of Byte;
    I:Integer; L:LongInt; DepMin,DepMax,DepMen:Single;
    Tr:PTrace;
Begin
 Tr:=TracePtr(Idx);
 If (Idx<1) Or (Idx>MaxTraces) Or (Tr=Nil) Or Not Tr^.Used Then Begin Say('No such trace.'); Exit; End;
 For I:=0 To 69 Do Floats[I]:=-12345.0;
 For I:=0 To 39 Do Ints[I]:=-12345;
 For I:=1 To 192 Do Buf[I]:=32;
 UpdateStats(Tr^,DepMin,DepMax,DepMen);
 Floats[0]:=Tr^.Delta; Floats[1]:=DepMin; Floats[2]:=DepMax; Floats[3]:=DepMen;
 Floats[5]:=Tr^.B; Floats[6]:=Tr^.E; Floats[7]:=Tr^.O; Floats[8]:=Tr^.A;
 Ints[6]:=6; Ints[9]:=Tr^.Npts; Ints[15]:=1;
 Assign(F,FileName); {$I-} Rewrite(F,1); {$I+}
 If IOResult<>0 Then Begin Say('Cannot write '+FileName); Exit; End;
 BlockWrite(F,Floats,SizeOf(Floats));
 BlockWrite(F,Ints,SizeOf(Ints));
 BlockWrite(F,Buf,SizeOf(Buf));
 For L:=1 To Tr^.Npts Do BlockWrite(F,Tr^.Data[L],SizeOf(Single));
 Close(F);
 Say('Wrote '+FileName+'.');
End;

Procedure WriteAscii(FileName:String; Idx:Integer);
Var F:Text; I:LongInt;
    Tr:PTrace;
Begin
 Tr:=TracePtr(Idx);
 If (Idx<1) Or (Idx>MaxTraces) Or (Tr=Nil) Or Not Tr^.Used Then Begin Say('No such trace.'); Exit; End;
 Assign(F,FileName); {$I-} Rewrite(F); {$I+}
 If IOResult<>0 Then Begin Say('Cannot write '+FileName); Exit; End;
 For I:=1 To Tr^.Npts Do WriteLn(F,Tr^.Data[I]:0:8);
 Close(F);
 Say('Wrote ASCII '+FileName+'.');
End;

Procedure ForEachTraceMath(Op:String; Arg:Single);
Var T:Integer; I:LongInt; X:Single; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  For I:=1 To Tr^.Npts Do Begin
   X:=Tr^.Data[I];
   If Op='ABS' Then X:=Abs(X)
    Else If Op='ADD' Then X:=X+Arg
    Else If Op='SUB' Then X:=X-Arg
    Else If Op='MUL' Then X:=X*Arg
    Else If Op='DIV' Then If Arg<>0 Then X:=X/Arg
    Else If Op='SQR' Then X:=X*X
    Else If Op='SQRT' Then If X>=0 Then X:=Sqrt(X) Else X:=0
    Else If Op='EXP' Then X:=Exp(X)
    Else If Op='EXP10' Then X:=Exp(Ln(10.0)*X)
    Else If Op='LOG' Then If X>0 Then X:=Ln(X) Else X:=0
    Else If Op='LOG10' Then If X>0 Then X:=Ln(X)/Ln(10.0) Else X:=0
    Else If Op='INT' Then X:=Trunc(X)
    Else If Op='FLOOR' Then X:=Int(X)
    Else If Op='REVERSE' Then X:=-X;
   Tr^.Data[I]:=X;
  End;
 End;
 End;
 Say(Op+' done.');
End;

Procedure BinaryFileOp(Op,FileName:String);
Var Idx,T:Integer; Other:TTrace; I,N:LongInt; Tr,Scratch:PTrace;
Begin
 Idx:=FirstFreeTrace;
 If Idx=0 Then Begin Say('No scratch slot for file operation.'); Exit; End;
 ReadSacBinary(FileName);
 Scratch:=TracePtr(Idx);
 If (Scratch=Nil) Or Not Scratch^.Used Then Exit;
 Other:=Scratch^; InitTrace(Scratch^);
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=Tr^.Npts; If Other.Npts<N Then N:=Other.Npts;
  For I:=1 To N Do Begin
   If Op='ADDF' Then Tr^.Data[I]:=Tr^.Data[I]+Other.Data[I]
    Else If Op='SUBF' Then Tr^.Data[I]:=Tr^.Data[I]-Other.Data[I]
    Else If Op='MULF' Then Tr^.Data[I]:=Tr^.Data[I]*Other.Data[I]
    Else If Op='DIVF' Then If Other.Data[I]<>0 Then Tr^.Data[I]:=Tr^.Data[I]/Other.Data[I];
  End;
 End;
 End;
 Say(Op+' done.');
End;

Procedure RemoveMean;
Var T:Integer; I:LongInt; MinV,MaxV,MeanV:Single; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  UpdateStats(Tr^,MinV,MaxV,MeanV);
  For I:=1 To Tr^.Npts Do Tr^.Data[I]:=Tr^.Data[I]-MeanV;
 End;
 End;
 Say('RMEAN done.');
End;

Procedure RemoveTrend;
Var T:Integer; I,N:LongInt; SX,SY,SXX,SXY,A,B,Den,X:Real; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=Tr^.Npts; If N<2 Then Continue;
  SX:=0; SY:=0; SXX:=0; SXY:=0;
  For I:=1 To N Do Begin
   X:=I; SX:=SX+X; SY:=SY+Tr^.Data[I]; SXX:=SXX+X*X; SXY:=SXY+X*Tr^.Data[I];
  End;
  Den:=N*SXX-SX*SX;
  If Den<>0 Then Begin
   B:=(N*SXY-SX*SY)/Den; A:=(SY-B*SX)/N;
   For I:=1 To N Do Tr^.Data[I]:=Tr^.Data[I]-(A+B*I);
  End;
 End;
 End;
 Say('RTREND/LINEFIT done.');
End;

Procedure Differentiate;
Var T:Integer; I:LongInt; Prev,Cur,D:Single; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used And (Tr^.Npts>1) Then Begin
  D:=Tr^.Delta; If D=0 Then D:=1;
  Prev:=Tr^.Data[1];
  For I:=2 To Tr^.Npts Do Begin
   Cur:=Tr^.Data[I];
   Tr^.Data[I-1]:=(Cur-Prev)/D;
   Prev:=Cur;
  End;
  Dec(Tr^.Npts); UpdateEndTime(Tr^);
 End;
 End;
 Say('DIF done.');
End;

Procedure Integrate;
Var T:Integer; I:LongInt; Sum,D:Single; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  Sum:=0; D:=Tr^.Delta;
  For I:=1 To Tr^.Npts Do Begin
   Sum:=Sum+Tr^.Data[I]*D; Tr^.Data[I]:=Sum;
  End;
 End;
 End;
 Say('INT integration done.');
End;

Procedure Smooth(Width:Integer);
Var T:Integer; I,J,C,N:LongInt; Tmp:TSampleArray; Sum:Real; Tr:PTrace;
Begin
 If Width<1 Then Width:=3;
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=Tr^.Npts;
  For I:=1 To N Do Begin
   Sum:=0; C:=0;
   For J:=I-Width To I+Width Do If (J>=1) And (J<=N) Then Begin Sum:=Sum+Tr^.Data[J]; Inc(C); End;
   If C>0 Then Tmp[I]:=Sum/C Else Tmp[I]:=Tr^.Data[I];
  End;
  For I:=1 To N Do Tr^.Data[I]:=Tmp[I];
 End;
 End;
 Say('SMOOTH done.');
End;

Procedure Taper(Pct:Single);
Var T:Integer; I,N,M:LongInt; W:Single; Tr:PTrace;
Begin
 If Pct<=0 Then Pct:=0.05;
 If Pct>0.5 Then Pct:=0.5;
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=Tr^.Npts; M:=Trunc(N*Pct);
  If M<1 Then Continue;
  For I:=1 To M Do Begin
   W:=0.5*(1.0-Cos(PiValue*(I-1)/M));
   Tr^.Data[I]:=Tr^.Data[I]*W;
   Tr^.Data[N-I+1]:=Tr^.Data[N-I+1]*W;
  End;
 End;
 End;
 Say('TAPER/HANNING done.');
End;

Procedure Decimate(Factor:Integer);
Var T:Integer; I,N:LongInt; Tr:PTrace;
Begin
 If Factor<2 Then Factor:=2;
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=0; I:=1;
  While I<=Tr^.Npts Do Begin Inc(N); Tr^.Data[N]:=Tr^.Data[I]; I:=I+Factor; End;
  Tr^.Npts:=N; Tr^.Delta:=Tr^.Delta*Factor; UpdateEndTime(Tr^);
 End;
 End;
 Say('DECIMATE done.');
End;

Procedure CutTraces(BegT,EndT:Single);
Var T:Integer; I,S1,S2,N:LongInt; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  S1:=Trunc((BegT-Tr^.B)/Tr^.Delta)+1;
  S2:=Trunc((EndT-Tr^.B)/Tr^.Delta)+1;
  If S1<1 Then S1:=1; If S2>Tr^.Npts Then S2:=Tr^.Npts;
  If (S2<S1) Then Begin
   If CutErrMode='FATAL' Then Running:=False Else Say('CUT outside trace.');
  End Else Begin
   N:=0;
   For I:=S1 To S2 Do Begin Inc(N); Tr^.Data[N]:=Tr^.Data[I]; End;
   Tr^.Npts:=N; Tr^.B:=BegT; UpdateEndTime(Tr^);
  End;
 End;
 End;
 Say('CUT applied.');
End;

Procedure SimpleLowPass(Alpha:Single);
Var T:Integer; I:LongInt; Y:Single; Tr:PTrace;
Begin
 If Alpha<=0 Then Alpha:=0.25; If Alpha>1 Then Alpha:=1;
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used And (Tr^.Npts>0) Then Begin
  Y:=Tr^.Data[1];
  For I:=2 To Tr^.Npts Do Begin
   Y:=Y+Alpha*(Tr^.Data[I]-Y); Tr^.Data[I]:=Y;
  End;
 End;
 End;
 Say('LOWPASS approximation done.');
End;

Procedure SimpleHighPass(Alpha:Single);
Var T:Integer; I:LongInt; Y,PrevX,X:Single; Tr:PTrace;
Begin
 If Alpha<=0 Then Alpha:=0.95; If Alpha>1 Then Alpha:=1;
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used And (Tr^.Npts>0) Then Begin
  Y:=0; PrevX:=Tr^.Data[1];
  For I:=2 To Tr^.Npts Do Begin
   X:=Tr^.Data[I];
   Y:=Alpha*(Y+X-PrevX); Tr^.Data[I]:=Y; PrevX:=X;
  End;
 End;
 End;
 Say('HIGHPASS approximation done.');
End;

Procedure DoFFT;
Var T:Integer; K,J,N:LongInt; Ang,C,S:Real; Re,Im:Real; Tmp:TSampleArray; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=Tr^.Npts;
  If N<1 Then Continue;
  If Tr^.FftRe=Nil Then New(Tr^.FftRe);
  If Tr^.FftIm=Nil Then New(Tr^.FftIm);
  Tr^.FftN:=N; Tr^.FftDelta:=Tr^.Delta;
  For K:=1 To N Do Begin
   Re:=0.0; Im:=0.0;
   For J:=1 To N Do Begin
    Ang:=-2.0*PiValue*(K-1)*(J-1)/N;
    C:=Cos(Ang); S:=Sin(Ang);
    Re:=Re+Tr^.Data[J]*C;
    Im:=Im+Tr^.Data[J]*S;
   End;
   Tr^.FftRe^[K]:=Re;
   Tr^.FftIm^[K]:=Im;
   Tmp[K]:=Sqrt(Re*Re+Im*Im);
  End;
  For K:=1 To N Do Tr^.Data[K]:=Tmp[K];
  If (N>0) And (Tr^.Delta<>0) Then Tr^.Delta:=1.0/(N*Tr^.Delta);
  Tr^.B:=0.0; UpdateEndTime(Tr^);
  Tr^.FileName:=Tr^.FileName+':FFT';
 End;
 End;
 Say('FFT done.');
End;

Procedure DoIFFT;
Var T:Integer; K,J,N:LongInt; Ang,C,S:Real; Sum:Real; Tmp:TSampleArray; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  N:=Tr^.FftN;
  If N<1 Then Begin Say('IFFT: no saved FFT for a trace.'); Continue; End;
  If (Tr^.FftRe=Nil) Or (Tr^.FftIm=Nil) Then Begin Say('IFFT: no saved FFT buffers.'); Continue; End;
  For J:=1 To N Do Begin
   Sum:=0.0;
   For K:=1 To N Do Begin
    Ang:=2.0*PiValue*(K-1)*(J-1)/N;
    C:=Cos(Ang); S:=Sin(Ang);
    Sum:=Sum+Tr^.FftRe^[K]*C-Tr^.FftIm^[K]*S;
   End;
   Tmp[J]:=Sum/N;
  End;
  Tr^.Npts:=N;
  For J:=1 To N Do Tr^.Data[J]:=Tmp[J];
  Tr^.Delta:=Tr^.FftDelta;
  Tr^.B:=0.0; UpdateEndTime(Tr^);
  Tr^.FileName:=Tr^.FileName+':IFFT';
 End;
 End;
 Say('IFFT done.');
End;

Procedure ListHdr;
Var T:Integer; MinV,MaxV,MeanV:Single; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  UpdateStats(Tr^,MinV,MaxV,MeanV);
  WriteLn('Trace ',T,' file=',Tr^.FileName);
  WriteLn('  npts=',Tr^.Npts,' delta=',Tr^.Delta:0:6,' b=',Tr^.B:0:6,' e=',Tr^.E:0:6);
  WriteLn('  depmin=',MinV:0:6,' depmax=',MaxV:0:6,' depmen=',MeanV:0:6);
 End;
 End;
End;

Procedure PlotAscii;
Var T:Integer; I,J,Col,N:LongInt; MinV,MaxV,MeanV,V:Single; Line:String; Tr:PTrace;
Begin
 For T:=1 To MaxTraces Do Begin
  Tr:=TracePtr(T);
  If (Tr<>Nil) And Tr^.Used Then Begin
  UpdateStats(Tr^,MinV,MaxV,MeanV);
  If MaxV=MinV Then MaxV:=MinV+1;
  WriteLn('Trace ',T,' ',Tr^.FileName);
  N:=Tr^.Npts; If N>80 Then N:=80;
  For I:=1 To N Do Begin
   V:=Tr^.Data[I];
   Col:=1+Trunc((V-MinV)/(MaxV-MinV)*59);
   Line:='';
   For J:=1 To 60 Do If J=Col Then Line:=Line+'*' Else If J=30 Then Line:=Line+'|' Else Line:=Line+' ';
   WriteLn(Line);
  End;
 End;
 End;
End;

Procedure GenerateData(Kind:String; N:LongInt; Delta:Single);
Var Idx:Integer; I:LongInt; X:Real; Tr:PTrace;
Begin
 Idx:=FirstFreeTrace;
 If Idx=0 Then Begin Say('No free trace slots.'); Exit; End;
 Tr:=TracePtr(Idx);
 If Tr=Nil Then Exit;
 If N<1 Then N:=256; If N>MaxSamples Then N:=MaxSamples;
 InitTrace(Tr^); Tr^.Used:=True; Tr^.FileName:='DATAGEN'; Tr^.Npts:=N; Tr^.Delta:=Delta;
 Randomize;
 For I:=1 To N Do Begin
  X:=2*PiValue*(I-1)/N;
  If Kind='IMPULSE' Then Begin If I=N Div 2 Then Tr^.Data[I]:=1 Else Tr^.Data[I]:=0; End
   Else If Kind='STEP' Then Begin If I>N Div 2 Then Tr^.Data[I]:=1 Else Tr^.Data[I]:=0; End
   Else If Kind='RAMP' Then Tr^.Data[I]:=I/N
   Else If Kind='SEISMOGRAM' Then
    Tr^.Data[I]:=Exp(-0.035*I)*(Sin(0.42*I)+0.45*Sin(1.15*I)+0.18*Sin(2.75*I))
   Else If Kind='NOISE' Then Tr^.Data[I]:=(Random(20000)-10000)/10000.0
   Else Tr^.Data[I]:=Sin(X);
 End;
 UpdateEndTime(Tr^);
 Say('Generated '+Kind+' trace.');
End;

Procedure DeleteChannel(N:Integer);
Var Tr:PTrace;
Begin
 Tr:=TracePtr(N);
 If (N>=1) And (N<=MaxTraces) And (Tr<>Nil) Then Begin InitTrace(Tr^); Say('Channel deleted.'); End
  Else Say('Bad channel.');
End;

Procedure SortTraces;
Var I,J:Integer; Tmp:TTrace; A,B:PTrace;
Begin
 For I:=1 To MaxTraces-1 Do For J:=I+1 To MaxTraces Do Begin
  A:=TracePtr(I); B:=TracePtr(J);
  If (A<>Nil) And (B<>Nil) And B^.Used And ((Not A^.Used) Or (B^.FileName<A^.FileName)) Then Begin
   Tmp:=A^; A^:=B^; B^:=Tmp;
  End;
 End;
 Say('SORT done.');
End;

Procedure ExecuteLine(Line:String); Forward;

Procedure RunScript(FileName:String);
Var F:Text; Line:String;
Begin
 Assign(F,FileName); {$I-} Reset(F); {$I+}
 If IOResult<>0 Then Begin Say('Cannot open macro '+FileName); Exit; End;
 While Not Eof(F) And Running Do Begin
  ReadLn(F,Line);
  ExecuteLine(Line);
 End;
 Close(F);
End;

Procedure LoadStartupArgument(FileName:String);
Begin
 If FileExt(FileName)='.SAC' Then ReadSacBinary(FileName)
  Else RunScript(FileName);
End;

Procedure DispatchCommand(N:Integer; Var Tok:TTokens); Forward;

Procedure DispatchCommand(N:Integer; Var Tok:TTokens);
Var Cmd,S:String; I:Integer; R:Single; L:LongInt; Tr:PTrace;
Begin
 Cmd:=UpCaseStr(Tok[1]);
 If Cmd='' Then Exit;
 If Not IsCommandKnown(Cmd) Then Begin Say('Unknown command: '+Cmd); Exit; End;

 If Cmd='HELP' Then Begin If N=1 Then WriteCommandList Else Say(Tok[2]+': commande SAC reconnue.'); Exit; End;
 If Cmd='ABOUT' Then Begin Say('Geophysix - SAC-compatible console, phases noyau/moteur/commandes.'); Exit; End;
 If Cmd='QUIT' Then Begin Running:=False; Exit; End;
 If Cmd='QUITSUB' Then Begin InSub:=False; Say('Leaving subprocess.'); Exit; End;
 If Cmd='NULL' Then Exit;
 If Cmd='ECHO' Then Begin S:=''; For I:=2 To N Do S:=S+Tok[I]+' '; Say(S); Exit; End;
 If Cmd='MESSAGE' Then Begin S:=''; For I:=2 To N Do S:=S+Tok[I]+' '; Say(S); Exit; End;
 If Cmd='PAUSE' Then Begin Say('Press ENTER.'); ReadLn; Exit; End;
 If Cmd='WAIT' Then Begin WaitMs(ToInt(Tok[2],1)*1000); Exit; End;
 If Cmd='HISTORY' Then Begin ShowHistory; Exit; End;
 If Cmd='SETBB' Then Begin If N>=3 Then SetBBVar(Tok[2],Tok[3]); Exit; End;
 If Cmd='GETBB' Then Begin
  If N>=2 Then Say(GetBBVar(Tok[2])) Else
  For I:=1 To BBCount Do Say(BB[I].Name+'='+BB[I].Value);
  Exit;
 End;
 If Cmd='UNSETBB' Then Begin If N>=2 Then UnsetBBVar(Tok[2]); Exit; End;
 If Cmd='TRANSCRIPT' Then Begin
  If (N>=2) And (UpCaseStr(Tok[2])='OFF') Then Begin
   If TranscriptOn Then Close(TranscriptFile);
   TranscriptOn:=False;
   Say('Transcript off.');
  End
   Else
  Begin
   If N>=2 Then S:=Tok[2]
           Else S:='sac.trn';
   Assign(TranscriptFile,S);
   Rewrite(TranscriptFile);
   TranscriptOn:=True; Say('Transcript on: '+S);
  End;
  Exit;
 End;
 If Cmd='SYSTEMCOMMAND' Then Begin
  S:=''; For I:=2 To N Do S:=S+Tok[I]+' ';
  SwapVectors; Exec(GetEnv('COMSPEC'),'/C '+S); SwapVectors; Exit;
 End;

 If Cmd='READ' Then Begin For I:=2 To N Do ReadSacBinary(Tok[I]); Exit; End;
 If Cmd='READTABLE' Then Begin For I:=2 To N Do ReadAscii(Tok[I]); Exit; End;
 If Cmd='READHDR' Then Begin For I:=2 To N Do ReadSacBinary(Tok[I]); ListHdr; Exit; End;
 If (Cmd='READBBF') Or (Cmd='READCSS') Or (Cmd='READDB') Or (Cmd='READGSE') Or
    (Cmd='READSDD') Or (Cmd='READSP') Or (Cmd='READSUDS') Or (Cmd='READCOR') Then Begin
  Unsupported(Cmd+' format adapter'); Exit;
 End;
 If Cmd='WRITE' Then Begin If N>=2 Then WriteSacBinary(Tok[2],1) Else WriteSacBinary('out.sac',1); Exit; End;
 If Cmd='WRITETABLE' Then Begin If N>=2 Then WriteAscii(Tok[2],1); Exit; End;
 If Cmd='WRITEHDR' Then Begin If N>=2 Then WriteSacBinary(Tok[2],1); Exit; End;
 If (Cmd='WRITEBBF') Or (Cmd='WRITECSS') Or (Cmd='WRITEGSE') Or (Cmd='WRITESDD') Or
    (Cmd='WRITESP') Or (Cmd='WRITECOR') Or (Cmd='WRITESPE') Then Begin
  Unsupported(Cmd+' format adapter'); Exit;
 End;
 If Cmd='READERR' Then Begin If N>=2 Then ReadErrMode:=UpCaseStr(Tok[2]); Say('READERR '+ReadErrMode); Exit; End;

 If Cmd='DATAGEN' Then Begin
  S:='SINE'; If N>=2 Then S:=UpCaseStr(Tok[2]);
  L:=256; If N>=3 Then L:=ToInt(Tok[3],256);
  R:=1.0; If N>=4 Then R:=ToReal(Tok[4],1.0);
  GenerateData(S,L,R); Exit;
 End;
 If (Cmd='FUNCGEN') Or (Cmd='FG') Then Begin
  S:='SINE'; If N>=2 Then S:=UpCaseStr(Tok[2]);
  GenerateData(S,ToInt(Tok[3],256),ToReal(Tok[4],1.0)); Exit;
 End;
 If Cmd='LISTHDR' Then Begin ListHdr; Exit; End;
 If Cmd='FILEID' Then Begin
  For I:=1 To MaxTraces Do Begin
   Tr:=TracePtr(I);
   If (Tr<>Nil) And Tr^.Used Then Say(Tr^.FileName);
  End;
  Exit;
 End;
 If Cmd='FILENUMBER' Then Begin Say('Files in memory: '+Chr(Ord('0')+TraceCount)); Exit; End;
 If Cmd='DELETECHANNEL' Then Begin DeleteChannel(ToInt(Tok[2],1)); Exit; End;
 If Cmd='ERASE' Then Begin ClearTraces; Say('Workspace cleared.'); Exit; End;
 If Cmd='COMMIT' Then Begin CommitTraces; Exit; End;
 If (Cmd='ROLLBACK') Or (Cmd='RECALLTRACE') Then Begin RollbackTraces; Exit; End;
 If Cmd='COPYHDR' Then Begin Unsupported(Cmd); Exit; End;
 If Cmd='CHNHDR' Then Begin
  If N>=3 Then For I:=1 To MaxTraces Do Begin
   Tr:=TracePtr(I);
   If (Tr<>Nil) And Tr^.Used Then Begin
    If UpCaseStr(Tok[2])='DELTA' Then Tr^.Delta:=ToReal(Tok[3],Tr^.Delta);
    If UpCaseStr(Tok[2])='B' Then Tr^.B:=ToReal(Tok[3],Tr^.B);
    If UpCaseStr(Tok[2])='O' Then Tr^.O:=ToReal(Tok[3],Tr^.O);
    If UpCaseStr(Tok[2])='A' Then Tr^.A:=ToReal(Tok[3],Tr^.A);
    UpdateEndTime(Tr^);
   End;
  End;
  Say('CHNHDR done.'); Exit;
 End;

 If (Cmd='ABS') Or (Cmd='SQR') Or (Cmd='SQRT') Or (Cmd='EXP') Or (Cmd='EXP10') Or
    (Cmd='LOG') Or (Cmd='LOG10') Or (Cmd='FLOOR') Or (Cmd='REVERSE') Then Begin ForEachTraceMath(Cmd,0); Exit; End;
 If (Cmd='ADD') Or (Cmd='SUB') Or (Cmd='MUL') Or (Cmd='DIV') Then Begin ForEachTraceMath(Cmd,ToReal(Tok[2],0.0)); Exit; End;
 If (Cmd='ADDF') Or (Cmd='SUBF') Or (Cmd='MULF') Or (Cmd='DIVF') Then Begin If N>=2 Then BinaryFileOp(Cmd,Tok[2]); Exit; End;
 If Cmd='RMEAN' Then Begin RemoveMean; Exit; End;
 If (Cmd='RTREND') Or (Cmd='LINEFIT') Then Begin RemoveTrend; Exit; End;
 If Cmd='DIF' Then Begin Differentiate; Exit; End;
 If Cmd='INT' Then Begin Integrate; Exit; End;
 If Cmd='RMS' Then Begin ForEachTraceMath('SQR',0); Smooth(8); ForEachTraceMath('SQRT',0); Exit; End;
 If Cmd='SMOOTH' Then Begin Smooth(ToInt(Tok[2],3)); Exit; End;
 If (Cmd='TAPER') Or (Cmd='HANNING') Then Begin Taper(ToReal(Tok[2],0.05)); Exit; End;
 If Cmd='DECIMATE' Then Begin Decimate(ToInt(Tok[2],2)); Exit; End;
 If Cmd='QUANTIZE' Then Begin ForEachTraceMath('INT',0); Exit; End;
 If Cmd='LOWPASS' Then Begin SimpleLowPass(ToReal(Tok[2],0.25)); Exit; End;
 If Cmd='HIGHPASS' Then Begin SimpleHighPass(ToReal(Tok[2],0.95)); Exit; End;
 If Cmd='BANDPASS' Then Begin SimpleHighPass(0.95); SimpleLowPass(0.25); Exit; End;
 If Cmd='BANDREJ' Then Begin Unsupported(Cmd+' exact filter'); Exit; End;
 If Cmd='FFT' Then Begin DoFFT; Exit; End;
 If Cmd='IFFT' Then Begin DoIFFT; Exit; End;
 If (Cmd='ENVELOPE') Or (Cmd='HILBERT') Or
    (Cmd='CONVOLVE') Or (Cmd='CORRELATE') Or (Cmd='WHITEN') Or (Cmd='WIENER') Or
    (Cmd='INTERPOLATE') Or (Cmd='MERGE') Or (Cmd='STRETCH') Or (Cmd='UNWRAP') Or
    (Cmd='DIVOMEGA') Or (Cmd='MULOMEGA') Then Begin Unsupported(Cmd+' numerical module'); Exit; End;
 If Cmd='CUT' Then Begin
  If N>=3 Then Begin CutOn:=True; CutB:=ToReal(Tok[2],0); CutE:=ToReal(Tok[3],0); CutTraces(CutB,CutE); End
   Else If (N>=2) And (UpCaseStr(Tok[2])='OFF') Then Begin CutOn:=False; Say('CUT off.'); End;
  Exit;
 End;
 If Cmd='CUTERR' Then Begin If N>=2 Then CutErrMode:=UpCaseStr(Tok[2]); Say('CUTERR '+CutErrMode); Exit; End;
 If Cmd='CUTIM' Then Begin If N>=3 Then CutTraces(ToReal(Tok[2],0),ToReal(Tok[3],0)); Exit; End;
 If Cmd='SORT' Then Begin SortTraces; Exit; End;
 If Cmd='SYNCHRONIZE' Then Begin
  For I:=1 To MaxTraces Do Begin
   Tr:=TracePtr(I);
   If (Tr<>Nil) And Tr^.Used Then Tr^.B:=0;
  End;
  Say('SYNCHRONIZE done.'); Exit;
 End;
 If Cmd='ROTATE' Then Begin Unsupported(Cmd+' 3-component operation'); Exit; End;

 If (Cmd='PLOT') Or (Cmd='PLOT1') Or (Cmd='PLOT2') Or (Cmd='PLOTC') Or
    (Cmd='PLOTXY') Or (Cmd='PLOTDY') Or (Cmd='PLOTPK') Or (Cmd='PLOTPM') Or
    (Cmd='PLOTSP') Or (Cmd='PRINT') Then Begin PlotAscii; Exit; End;
 If (Cmd='SAVEIMG') Or (Cmd='IMAGE') Or (Cmd='CONTOUR') Or (Cmd='SPECTROGRAM') Or
    (Cmd='SONOGRAM') Or (Cmd='MAP') Or (Cmd='ARRAYMAP') Then Begin Unsupported(Cmd+' graphics backend'); Exit; End;
 If (Cmd='AXES') Or (Cmd='BORDER') Or (Cmd='COLOR') Or (Cmd='FILEID') Or
    (Cmd='GRAYSCALE') Or (Cmd='GRID') Or (Cmd='GTEXT') Or (Cmd='LINE') Or
    (Cmd='LINLIN') Or (Cmd='LINLOG') Or (Cmd='LOGLIN') Or (Cmd='LOGLOG') Or
    (Cmd='LOGLAB') Or (Cmd='PICKAUTHOR') Or (Cmd='PICKPHASE') Or (Cmd='PICKPREFS') Or
    (Cmd='PICKS') Or (Cmd='PLABEL') Or (Cmd='PLOTALPHA') Or (Cmd='PLOTCTABLE') Or
    (Cmd='PLOTPKTABLE') Or (Cmd='SYMBOL') Or (Cmd='TICKS') Or (Cmd='TITLE') Or
    (Cmd='TSIZE') Or (Cmd='VSPACE') Or (Cmd='WIDTH') Or (Cmd='WINDOW') Or
    (Cmd='XDIV') Or (Cmd='XFUDGE') Or (Cmd='XFULL') Or (Cmd='XGRID') Or
    (Cmd='XLABEL') Or (Cmd='XLIM') Or (Cmd='XLIN') Or (Cmd='XLOG') Or
    (Cmd='XVPORT') Or (Cmd='YDIV') Or (Cmd='YFUDGE') Or (Cmd='YFULL') Or
    (Cmd='YGRID') Or (Cmd='YLABEL') Or (Cmd='YLIM') Or (Cmd='YLIN') Or
    (Cmd='YLOG') Or (Cmd='YVPORT') Or (Cmd='ZCOLORS') Or (Cmd='ZLABELS') Or
    (Cmd='ZLEVELS') Or (Cmd='ZLINES') Or (Cmd='ZTICKS') Then Begin
  Say(Cmd+' option stored/accepted in console mode.'); Exit;
 End;

 If (Cmd='MACRO') Or (Cmd='LOAD') Or (Cmd='CAPF') Then Begin
  If N>=2 Then RunScript(Tok[2])
          Else Say('Macro file missing.');
  Exit;
 End;
 If (Cmd='INSTALLMACRO') Or (Cmd='SETMACRO') Then Begin Say(Cmd+' accepted; use MACRO filename to execute.'); Exit; End;
 If Cmd='EVALUATE' Then Begin If N>=4 Then SetBBVar(Tok[2],Tok[4]); Exit; End;
 If Cmd='REPORT' Then Begin ListHdr; Exit; End;
 If Cmd='TRACE' Then Begin Unsupported(Cmd+' interactive picking'); Exit; End;

 If (Cmd='ADDSTACK') Or (Cmd='CHANGESTACK') Or (Cmd='DELETESTACK') Or
    (Cmd='DELTACHECK') Or (Cmd='DISTANCEAXIS') Or (Cmd='DISTANCEWINDOW') Or
    (Cmd='GLOBALSTACK') Or (Cmd='INCREMENTSTACK') Or (Cmd='LISTSTACK') Or
    (Cmd='PLOTRECORDSECTION') Or (Cmd='PLOTSTACK') Or (Cmd='SUMSTACK') Or
    (Cmd='TIMEAXIS') Or (Cmd='TIMEWINDOW') Or (Cmd='SSSTRAVELTIME') Or
    (Cmd='VELOCITYMODEL') Or (Cmd='VELOCITYROSET') Or (Cmd='WRITESTACK') Or
    (Cmd='ZEROSTACK') Then Begin Unsupported(Cmd+' stacking subprocess'); Exit; End;
 If (Cmd='COR') Or (Cmd='MEM') Or (Cmd='MLM') Or (Cmd='PDS') Or (Cmd='PLOTCOR') Or
    (Cmd='PLOTPE') Or (Cmd='PLOTSPE') Then Begin Unsupported(Cmd+' spectral subprocess'); Exit; End;

 Unsupported(Cmd);
End;

Procedure ExecuteLine(Line:String);
Var Tok:TTokens; N:Integer;
Begin
 Line:=TrimStr(Line);
 If Line='' Then Exit;
 If (Line[1]='*') Or (Line[1]='#') Then Exit;
 SubstituteBB(Line);
 AddHistory(Line);
 N:=Tokenize(Line,Tok);
 If N>0 Then DispatchCommand(N,Tok);
End;

Procedure Help;
Begin
 WriteLn('SAC - Cette commande permet de lancer un clone console SAC (Seismic Analysis Code).');
 WriteLn;
 WriteLn('Syntaxe: SAC [macro.sac]');
 WriteLn('         SAC fichier.sac [autre.sac ...]');
 WriteLn;
 WriteLn('Commandes utiles implementees: READ WRITE READTABLE LISTHDR DATAGEN FG FUNCGEN');
 WriteLn('ADD SUB MUL DIV ADDF SUBF MULF DIVF ABS SQR SQRT EXP LOG RMEAN RTREND');
 WriteLn('DIF INT SMOOTH TAPER DECIMATE LOWPASS HIGHPASS CUT PLOT SETBB GETBB MACRO');
 WriteLn('Toutes les commandes SAC listees dans le manuel sont reconnues; les modules');
 WriteLn('graphiques, bases de donnees et sous-processus avances signalent leur etat.');
End;

Procedure Init;
Begin
 CreateTraceList(Traces);
 CreateTraceList(Saved);
 BBCount:=0; HistCount:=0; HistFirst:=Nil; HistLast:=Nil; Running:=True; InSub:=False;
 CutOn:=False; CutB:=0; CutE:=0; ReadErrMode:='WARNING'; CutErrMode:='WARNING';
 TranscriptOn:=False;
End;

Var
 Line:String;
 I:Integer;

BEGIN
 Init;
 If (ParamStr(1)='/?') Or (ParamStr(1)='--help') Or (ParamStr(1)='-h') Or
    (ParamStr(1)='/h') Or (ParamStr(1)='/H') Then Begin Help; Halt; End;
 Say('SAC - tapez HELP pour les commandes, QUIT pour quitter.');
 If ParamCount>=1 Then
  For I:=1 To ParamCount Do LoadStartupArgument(ParamStr(I));
 While Running Do Begin
  Write('SAC> ');
  ReadLn(Line);
  ExecuteLine(Line);
 End;
 If TranscriptOn Then Close(TranscriptFile);
END.
