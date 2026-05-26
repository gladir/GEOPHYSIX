{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)

  SEGYREAD - clone console de la commande segyread de Seismic Unix.

  Usage typique:

    SEGYREAD tape=test.segy verbose=1 | SEGYCLEAN > test.su

  Cette version lit un fichier SEG-Y, saute les en-tetes texte et binaire,
  convertit chaque trace en un flux SU simplifie, puis ecrit ce flux sur
  stdout. Les echantillons SEG-Y IBM float 4 octets, IEEE float 4 octets,
  entier 32 bits, entier 16 bits et entier 8 bits sont supportes.
}

Program SEGYREAD;

{$N+}

Const
 TextHeaderSize = 3200;
 BinHeaderSize  = 400;
 TraceHeaderSize = 240;
 MaxSamples = 16000;

Type
 TByteArray = Array[1..MaxSamples*4] Of Byte;
 PByteArray = ^TByteArray;
 TTraceHeader = Array[1..TraceHeaderSize] Of Byte;

Var
 InF,OutF:File;
 VerboseOut:Text;
 TapeName:String;
 Verbose:Integer;
 OverrideFormat,OverrideNS,OverrideDT:Integer;
 BinHdr:Array[1..BinHeaderSize] Of Byte;
 TextHdr:Array[1..TextHeaderSize] Of Byte;
 DataBuf:PByteArray;
 BinFormat,BinNS,BinDT:Integer;
 TraceNo:LongInt;

Function UpCaseStr(S:String):String;
Var I:Integer;
Begin
 For I:=1 To Length(S) Do S[I]:=UpCase(S[I]);
 UpCaseStr:=S;
End;

Function StartsWith(S,P:String):Boolean;
Begin
 StartsWith:=Copy(UpCaseStr(S),1,Length(P))=UpCaseStr(P);
End;

Function IntOf(S:String; Def:Integer):Integer;
Var V,Code:Integer;
Begin
 Val(S,V,Code);
 If Code=0 Then IntOf:=V Else IntOf:=Def;
End;

Procedure Help;Begin
 WriteLn('SEGYREAD - Cette commande permet de lire un fichier SEG-Y et ',
         #130+'crit un flux SU sur stdout');
 WriteLn;
 WriteLn('Syntaxe : SEGYREAD fichier.segy [optional parameters] > fichier.su');
 WriteLn('          SEGYREAD tape=fichier.segy [optional parameters] > fichier.su');
 WriteLn;
 WriteLn(' optional parameters:');
 WriteLn('  tape=nom       Fichier SEG-Y a lire');
 WriteLn('  verbose=0|1    Affiche des informations sur CON (defaut 0)');
 WriteLn('  format=n       Force le format echantillon SEG-Y');
 WriteLn('                 1=IBM float, 2=int32, 3=int16, 5=IEEE float, 8=int8');
 WriteLn('  ns=n           Force le nombre d''echantillons par trace');
 WriteLn('  dt=n           Force l''intervalle en microsecondes');
 WriteLn;
 WriteLn('Exemple : SEGYREAD tape=test.segy verbose=1 | SEGYCLEAN > test.su');
End;

Procedure Log(S:String);
Begin
 If Verbose<>0 Then WriteLn(VerboseOut,S);
End;

Procedure ParseArgs;
Var I:Integer; S:String;
Begin
 TapeName:='';
 Verbose:=0; OverrideFormat:=0; OverrideNS:=0; OverrideDT:=0;
 For I:=1 To ParamCount Do Begin
  S:=ParamStr(I);
  If StartsWith(S,'tape=') Then TapeName:=Copy(S,6,Length(S)-5)
   Else If StartsWith(S,'verbose=') Then Verbose:=IntOf(Copy(S,9,Length(S)-8),0)
   Else If StartsWith(S,'format=') Then OverrideFormat:=IntOf(Copy(S,8,Length(S)-7),0)
   Else If StartsWith(S,'ns=') Then OverrideNS:=IntOf(Copy(S,4,Length(S)-3),0)
   Else If StartsWith(S,'dt=') Then OverrideDT:=IntOf(Copy(S,4,Length(S)-3),0)
   Else If (Pos('=',S)=0) And (TapeName='') Then TapeName:=S;
 End;
End;

Function BE16(Var B; Pos:Integer):LongInt;
Var A:Array[1..65520] Of Byte Absolute B;
Begin
 BE16:=LongInt(A[Pos])*256+LongInt(A[Pos+1]);
End;

Function BE32(Var B; Pos:Integer):LongInt;
Var A:Array[1..65520] Of Byte Absolute B;
Begin
 If A[Pos]>=128 Then
  BE32:=LongInt(A[Pos]-256)*16777216+LongInt(A[Pos+1])*65536+
        LongInt(A[Pos+2])*256+LongInt(A[Pos+3])
 Else
  BE32:=LongInt(A[Pos])*16777216+LongInt(A[Pos+1])*65536+
        LongInt(A[Pos+2])*256+LongInt(A[Pos+3]);
End;

Function SampleSize(Fmt:Integer):Integer;
Begin
 Case Fmt Of
  1,2,5:SampleSize:=4;
  3:SampleSize:=2;
  8:SampleSize:=1;
  Else SampleSize:=4;
 End;
End;

Function Power16(E:Integer):Real;
Var I:Integer; R:Real;
Begin
 R:=1.0;
 If E>=0 Then For I:=1 To E Do R:=R*16.0
  Else For I:=1 To -E Do R:=R/16.0;
 Power16:=R;
End;

Function IBMToReal(B1,B2,B3,B4:Byte):Real;
Var Sign,Exp:Integer; Frac:LongInt; F:Real;
Begin
 If (B1=0) And (B2=0) And (B3=0) And (B4=0) Then Begin IBMToReal:=0.0; Exit; End;
 If (B1 And $80)<>0 Then Sign:=-1 Else Sign:=1;
 Exp:=(B1 And $7F)-64;
 Frac:=LongInt(B2)*65536+LongInt(B3)*256+LongInt(B4);
 F:=Frac/16777216.0;
 IBMToReal:=Sign*F*Power16(Exp);
End;

Function IEEEToReal(B1,B2,B3,B4:Byte):Single;
Var L:LongInt; R:Single Absolute L;
Begin
 L:=LongInt(B1)*16777216+LongInt(B2)*65536+LongInt(B3)*256+LongInt(B4);
 IEEEToReal:=R;
End;

Procedure PutLE16(Var H:TTraceHeader; Pos,Value:Integer);
Begin
 H[Pos]:=Value And 255;
 H[Pos+1]:=(Value Shr 8) And 255;
End;

Procedure PutLE32(Var H:TTraceHeader; Pos:Integer; Value:LongInt);
Begin
 H[Pos]:=Value And 255;
 H[Pos+1]:=(Value Shr 8) And 255;
 H[Pos+2]:=(Value Shr 16) And 255;
 H[Pos+3]:=(Value Shr 24) And 255;
End;

Procedure WriteFloatLE(X:Single);
Var L:LongInt Absolute X; B:Array[1..4] Of Byte;
Begin
 B[1]:=L And 255;
 B[2]:=(L Shr 8) And 255;
 B[3]:=(L Shr 16) And 255;
 B[4]:=(L Shr 24) And 255;
 BlockWrite(OutF,B,4);
End;

Procedure ZeroHeader(Var H:TTraceHeader);
Var I:Integer;
Begin
 For I:=1 To TraceHeaderSize Do H[I]:=0;
End;

Procedure MakeSUHeader(Var SegyH:TTraceHeader; Var SUH:TTraceHeader; NS,DT:Integer);
Begin
 ZeroHeader(SUH);
 PutLE32(SUH,1,TraceNo);
 PutLE32(SUH,5,TraceNo);
 PutLE16(SUH,29,1);
 PutLE16(SUH,115,NS);
 PutLE16(SUH,117,DT);
 { Quelques champs geometriques usuels sont recopies quand possible. }
 PutLE32(SUH,37,BE32(SegyH,37));
 PutLE32(SUH,41,BE32(SegyH,41));
 PutLE32(SUH,73,BE32(SegyH,73));
 PutLE32(SUH,77,BE32(SegyH,77));
End;

Function SampleValue(Fmt,Index:Integer):Single;
Var P:LongInt; V:LongInt; R:Real;
Begin
 P:=(Index-1)*SampleSize(Fmt)+1;
 Case Fmt Of
  1:Begin
     R:=IBMToReal(DataBuf^[P],DataBuf^[P+1],DataBuf^[P+2],DataBuf^[P+3]);
     SampleValue:=R;
    End;
  2:Begin
     V:=LongInt(DataBuf^[P])*16777216+LongInt(DataBuf^[P+1])*65536+
        LongInt(DataBuf^[P+2])*256+LongInt(DataBuf^[P+3]);
     SampleValue:=V;
    End;
  3:Begin
     V:=BE16(DataBuf^,P);
     If V>=32768 Then V:=V-65536;
     SampleValue:=V;
    End;
  5:SampleValue:=IEEEToReal(DataBuf^[P],DataBuf^[P+1],DataBuf^[P+2],DataBuf^[P+3]);
  8:Begin
     V:=DataBuf^[P];
     If V>=128 Then V:=V-256;
     SampleValue:=V;
    End;
  Else SampleValue:=0.0;
 End;
End;

Procedure OpenFiles;
Var Code:Integer;
Begin
 Assign(VerboseOut,'CON'); Rewrite(VerboseOut);
 If TapeName='' Then Begin
  WriteLn(VerboseOut,'SEGYREAD: nom de fichier SEG-Y manquant.');
  Halt(1);
 End;
 Assign(InF,TapeName); {$I-} Reset(InF,1); {$I+}
 Code:=IOResult;
 If Code<>0 Then Begin
  WriteLn(VerboseOut,'SEGYREAD: impossible d''ouvrir ',TapeName);
  Halt(1);
 End;
 Assign(OutF,''); Rewrite(OutF,1);
End;

Procedure ReadReelHeaders;
Var Got:Integer;
Begin
 BlockRead(InF,TextHdr,TextHeaderSize,Got);
 If Got<>TextHeaderSize Then Begin WriteLn(VerboseOut,'SEGYREAD: en-tete texte incomplet.'); Halt(1); End;
 BlockRead(InF,BinHdr,BinHeaderSize,Got);
 If Got<>BinHeaderSize Then Begin WriteLn(VerboseOut,'SEGYREAD: en-tete binaire incomplet.'); Halt(1); End;
 BinDT:=BE16(BinHdr,17);
 BinNS:=BE16(BinHdr,21);
 BinFormat:=BE16(BinHdr,25);
 If OverrideDT>0 Then BinDT:=OverrideDT;
 If OverrideNS>0 Then BinNS:=OverrideNS;
 If OverrideFormat>0 Then BinFormat:=OverrideFormat;
 If Verbose<>0 Then WriteLn(VerboseOut,'SEGYREAD: ns=',BinNS,' dt=',BinDT,
                            ' format=',BinFormat);
End;

Procedure ConvertTraces;
Var TH,SUH:TTraceHeader; Got,NS,OutNS,DT,Fmt,Bytes,I,SkipBytes,Chunk:Integer;
    X:Single; SkipBuf:Array[1..1024] Of Byte;
Begin
 TraceNo:=0;
 Repeat
  BlockRead(InF,TH,TraceHeaderSize,Got);
  If Got=0 Then Break;
  If Got<>TraceHeaderSize Then Begin Log('SEGYREAD: trace header incomplet ignore.'); Break; End;
  NS:=BE16(TH,115); DT:=BE16(TH,117); Fmt:=BinFormat;
  If NS=0 Then NS:=BinNS;
  If DT<=0 Then DT:=BinDT;
  If OverrideNS>0 Then NS:=OverrideNS;
  If OverrideDT>0 Then DT:=OverrideDT;
  If OverrideFormat>0 Then Fmt:=OverrideFormat;
  OutNS:=NS;
  If OutNS>MaxSamples Then Begin Log('SEGYREAD: trace tronquee a MaxSamples.'); OutNS:=MaxSamples; End;
  Bytes:=OutNS*SampleSize(Fmt);
  BlockRead(InF,DataBuf^,Bytes,Got);
  If Got<>Bytes Then Begin Log('SEGYREAD: donnees de trace incompletes.'); Break; End;
  SkipBytes:=(NS-OutNS)*SampleSize(Fmt);
  While SkipBytes>0 Do Begin
   If SkipBytes>SizeOf(SkipBuf) Then Chunk:=SizeOf(SkipBuf) Else Chunk:=SkipBytes;
   BlockRead(InF,SkipBuf,Chunk,Got);
   If Got<>Chunk Then Begin Log('SEGYREAD: fin pendant saut de trace.'); Break; End;
   SkipBytes:=SkipBytes-Chunk;
  End;
  Inc(TraceNo);
  MakeSUHeader(TH,SUH,OutNS,DT);
  BlockWrite(OutF,SUH,TraceHeaderSize);
  For I:=1 To OutNS Do Begin
   X:=SampleValue(Fmt,I);
   WriteFloatLE(X);
  End;
 Until False;
End;

BEGIN
 If(ParamStr(1)='/?')Or(ParamStr(1)='--help')Or(ParamStr(1)='-h')Or
   (ParamStr(1)='/h')Or(ParamStr(1)='/H')Then Begin
  Help;
  Halt;
 End;
 ParseArgs;
 New(DataBuf);
 OpenFiles;
 ReadReelHeaders;
 ConvertTraces;
 If Verbose<>0 Then WriteLn(VerboseOut,'SEGYREAD: traces=',TraceNo);
 Close(InF);
 Close(OutF);
 Dispose(DataBuf);
END.
