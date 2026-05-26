{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)

  SUXWIGB - clone graphique de la commande suxwigb de Seismic Unix.

  Le suxwigb original affiche des traces SU dans une fenetre X11. Cette
  version Turbo Pascal/Free Pascal lit un flux SU binaire sur stdin ou
  dans un fichier donne par in=, puis affiche les traces en mode graphique
  avec InitializeGraphics et PutPixel.

  Exemple:

    SUPLANE > plane.su
    SUXWIGB in=plane.su

  Parametres utiles:
    in=stdin         fichier SU d'entree; defaut stdin
    perc=99          percentile approximatif utilise pour l'echelle
    clip=value       clip absolu; prioritaire sur perc
    va=1             remplissage variable area positif
    wiggle=1         trace wiggle
}

Program SUXWIGB;

{$N+}
{$R-}

Uses {$IFDEF FPC}
      Crt,PtcGraph,PtcCrt,PtcMouse,DOS
     {$ELSE}
      Crt,Graph,DOS
     {$ENDIF};

Const
 MaxTraces = 256;
 MaxSamples = 4096;
 HeaderBytes = 240;

Type
 TSampleArray = Array[1..MaxSamples] Of Single;
 PSampleArray = ^TSampleArray;
 TTracePtrArray = Array[1..MaxTraces] Of PSampleArray;
 THeader = Array[1..HeaderBytes] Of Byte;

Var
 InF:File;
 Trace:TTracePtrArray;
 NTr,NS:Integer;
 DT:Integer;
 InName:String;
 WBox,HBox:Integer;
 PlotLeft,PlotTop,PlotW,PlotH:Integer;
 Va,Wiggle,Verbose:Integer;
 Perc,Clip:Real;

Procedure InitializeGraphics;
Var
 Driver, Mode: Integer;
 ErrCode: Integer;
Begin
 {$IFDEF FPC}
  Driver:=VGA;
  Mode:=VGAHi;
 {$ELSE}
  Driver:=Detect;
  Mode:=VGAHi;
 {$ENDIF}
 InitGraph(Driver,Mode,'');
 ErrCode:=GraphResult;
 If ErrCode=grOk Then Begin
  WBox:=GetMaxX+1;
  HBox:=GetMaxY+1;
  PlotLeft:=54;
  PlotTop:=28;
  PlotW:=WBox-PlotLeft-12;
  PlotH:=HBox-PlotTop-34;
  If PlotW<80 Then PlotW:=WBox;
  If PlotH<80 Then PlotH:=HBox;
  SetBkColor(White);
  ClearDevice;
  SetColor(White);
  SetLineStyle(0,0,1);
 End
  Else
 Begin
  WriteLn('Erreur graphique : ',GraphErrorMsg(ErrCode));
  Halt;
 End;
End;

{$IFNDEF FPC}
 Function MouseDriverFound: Boolean;
 Var
  Regs: Registers;
 Begin
  Regs.AX := 0;
  Intr($33, Regs);
  MouseDriverFound := Regs.AX = $FFFF;
 End;

 Procedure ShowMouse;
 Var
  Regs: Registers;
 Begin
  Regs.AX := $0001;
  Intr($33, Regs);
 End;

 Procedure HideMouse;
 Var
  Regs: Registers;
 Begin
  Regs.AX := $0002;
  Intr($33, Regs);
 End;

 Procedure GetMouseState(Var X, Y, Button: LongInt);
 Var
  Regs: Registers;
 Begin
  Regs.AX := $0003;
  Intr($33, Regs);
  Button := Regs.BX;
  X := Regs.CX;
  Y := Regs.DX;
 End;
{$ELSE}
 Function MouseDriverFound: Boolean;
 Begin
  MouseDriverFound := True;
 End;

 Procedure ShowMouse;
 Begin
  { Pas d'implémentation pour Free Pascal }
 End;

 Procedure HideMouse;
 Begin
  { Pas d'implémentation pour Free Pascal }
 End;
{$ENDIF}

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

Function RealOf(S:String; Def:Real):Real;
Var V:Real; Code:Integer;
Begin
 Val(S,V,Code);
 If Code=0 Then RealOf:=V Else RealOf:=Def;
End;

Procedure Help;
Begin
 WriteLn('SUXWIGB - Cette commande permet de créer un graphique ondulé de style ',
         'X-windows des données SU.');
 WriteLn;
 WriteLn('Syntaxe : SUXWIGB <stdin [parametres optionnels]');
 WriteLn('          SUXWIGB in=fichier.su [parametres optionnels]');
 WriteLn;
 WriteLn(' parametres optionnels:');
 WriteLn('  in=stdin         Fichier SU d''entree; defaut stdin');
 WriteLn('  perc=99          Percentile approximatif pour l''echelle');
 WriteLn('  clip=value       Clip absolu');
 WriteLn('  va=1             Remplissage variable area positif');
 WriteLn('  wiggle=1         Dessin des wiggles');
 WriteLn('  verbose=0|1      Messages diagnostiques');
 WriteLn;
 WriteLn('Exemple : SUPLANE > plane.su');
 WriteLn('          SUXWIGB in=plane.su');
End;

Procedure InitDefaults;
Begin
 InName:='';
 WBox:=800; HBox:=600;
 Va:=1; Wiggle:=1; Verbose:=0;
 Perc:=99.0; Clip:=0.0;
 NTr:=0; NS:=0; DT:=0;
End;

Procedure ParseArgs;
Var I:Integer; S:String;
Begin
 For I:=1 To ParamCount Do Begin
  S:=ParamStr(I);
  If StartsWith(S,'in=') Then InName:=Copy(S,4,Length(S)-3)
   Else If StartsWith(S,'perc=') Then Perc:=RealOf(Copy(S,6,Length(S)-5),Perc)
   Else If StartsWith(S,'clip=') Then Clip:=RealOf(Copy(S,6,Length(S)-5),Clip)
   Else If StartsWith(S,'va=') Then Va:=IntOf(Copy(S,4,Length(S)-3),Va)
   Else If StartsWith(S,'wiggle=') Then Wiggle:=IntOf(Copy(S,8,Length(S)-7),Wiggle)
   Else If StartsWith(S,'verbose=') Then Verbose:=IntOf(Copy(S,9,Length(S)-8),Verbose);
 End;
 If WBox<80 Then WBox:=80;
 If HBox<80 Then HBox:=80;
 If Perc<=0.0 Then Perc:=99.0;
 If Perc>100.0 Then Perc:=100.0;
End;

Function LE16(Var H:THeader; Pos:Integer):Integer;
Begin
 LE16:=H[Pos]+H[Pos+1]*256;
End;

Function ReadFloatLE(Var F:File; Var X:Single):Boolean;
Var Got:Integer;
    U:Record
     Case Integer Of
      0:(B:Array[1..4] Of Byte);
      1:(R:Single);
    End;
Begin
 BlockRead(F,U.B,4,Got);
 If Got<>4 Then Begin ReadFloatLE:=False; Exit; End;
 X:=U.R;
 ReadFloatLE:=True;
End;

Procedure SkipBytes(Count:LongInt);
Var Buf:Array[1..1024] Of Byte; Chunk,Got:Integer;
Begin
 While Count>0 Do Begin
  If Count>SizeOf(Buf) Then Chunk:=SizeOf(Buf) Else Chunk:=Count;
  BlockRead(InF,Buf,Chunk,Got);
  If Got<>Chunk Then Exit;
  Count:=Count-Chunk;
 End;
End;

Procedure ReadSU;
Var H:THeader; Got,Code:Integer; I,ThisNS,ReadNS:Integer; X:Single;
Begin
 If InName='' Then Assign(InF,'') Else Assign(InF,InName);
 {$I-} Reset(InF,1); {$I+}
 Code:=IOResult;
 If Code<>0 Then Begin
  WriteLn('SUXWIGB: impossible d''ouvrir ',InName);
  Exit;
 End;
 Repeat
  BlockRead(InF,H,HeaderBytes,Got);
  If Got=0 Then Break;
  If Got<>HeaderBytes Then Break;
  ThisNS:=LE16(H,115);
  If ThisNS<=0 Then Break;
  If NTr<MaxTraces Then Begin
   Inc(NTr);
   New(Trace[NTr]);
   For I:=1 To MaxSamples Do Trace[NTr]^[I]:=0.0;
   If NS=0 Then Begin
    NS:=ThisNS;
    DT:=LE16(H,117);
    If NS>MaxSamples Then NS:=MaxSamples;
   End;
   ReadNS:=ThisNS;
   If ReadNS>MaxSamples Then ReadNS:=MaxSamples;
   For I:=1 To ReadNS Do Begin
    If Not ReadFloatLE(InF,X) Then Break;
    If I<=NS Then Trace[NTr]^[I]:=X;
   End;
   If ThisNS>ReadNS Then SkipBytes(LongInt(ThisNS-ReadNS)*4);
   For I:=ReadNS+1 To NS Do Trace[NTr]^[I]:=0.0;
  End
   Else Begin
    SkipBytes(LongInt(ThisNS)*4);
   End;
 Until False;
 Close(InF);
End;

Function AbsR(X:Real):Real;
Begin
 If X<0 Then AbsR:=-X Else AbsR:=X;
End;

Function ComputeClip:Real;
Var T,I:Integer; M,A,Threshold:Real;
Begin
 If Clip>0.0 Then Begin ComputeClip:=Clip; Exit; End;
 M:=0.0;
 For T:=1 To NTr Do
  For I:=1 To NS Do Begin
   A:=AbsR(Trace[T]^[I]);
   If A>M Then M:=A;
  End;
 Threshold:=M*(Perc/100.0);
 If Threshold<=0.0000001 Then Threshold:=1.0;
 ComputeClip:=Threshold;
End;

Function SampleAt(T:Integer; Y:Integer):Real;
Var S0,S1:Integer; Pos,F:Real;
Begin
 If NS<=1 Then Begin SampleAt:=0.0; Exit; End;
 If PlotH<=1 Then Begin SampleAt:=Trace[T]^[1]; Exit; End;
 Pos:=1.0+(Y*(NS-1))/(PlotH-1);
 S0:=Trunc(Pos);
 If S0<1 Then S0:=1;
 If S0>=NS Then Begin SampleAt:=Trace[T]^[NS]; Exit; End;
 S1:=S0+1;
 F:=Pos-S0;
 SampleAt:=Trace[T]^[S0]*(1.0-F)+Trace[T]^[S1]*F;
End;

Function GrayPixel(X,Y:Integer; ClipVal:Real):Integer;
Var T,GV:Integer; Base,Curve,HalfGap,AmpScale,V:Real;
Begin
 GV:=255;
 If NTr<=0 Then Begin GrayPixel:=GV; Exit; End;
 If ClipVal<=0.0000001 Then ClipVal:=1.0;
 HalfGap:=PlotW/(NTr+1)/2.0;
 AmpScale:=HalfGap/ClipVal;
 For T:=1 To NTr Do Begin
  Base:=T*PlotW/(NTr+1);
  V:=SampleAt(T,Y);
  If V>ClipVal Then V:=ClipVal;
  If V<-ClipVal Then V:=-ClipVal;
  Curve:=Base+V*AmpScale;
  If (Va<>0) And (V>0.0) And (X>=Trunc(Base)) And (X<=Trunc(Curve)) Then Begin
   GV:=210;
  End;
  If (Wiggle<>0) And (AbsR(X-Curve)<=1.1) Then Begin
   GrayPixel:=0;
   Exit;
  End;
  If AbsR(X-Base)<=0.35 Then If GV>235 Then GV:=235;
 End;
 GrayPixel:=GV;
End;

Function GrayToColor(G:Integer):Integer;
Begin
 If G<=16 Then GrayToColor:=Black
  Else If G<230 Then GrayToColor:=LightGray
  Else If G<250 Then GrayToColor:=DarkGray
  Else GrayToColor:=White;
End;

Function IntStr(V:LongInt):String;
Var S:String;
Begin
 Str(V,S);
 IntStr:=S;
End;

Function RealStr(V:Real; Decimals:Integer):String;
Var S:String;
Begin
 If Decimals<0 Then Decimals:=0;
 Str(V:0:Decimals,S);
 RealStr:=S;
End;

Procedure DrawPixelHLine(X1,X2,Y,Color:Integer);
Var X,T:Integer;
Begin
 If Y<0 Then Exit;
 If Y>=HBox Then Exit;
 If X1>X2 Then Begin T:=X1; X1:=X2; X2:=T; End;
 If X1<0 Then X1:=0;
 If X2>=WBox Then X2:=WBox-1;
 For X:=X1 To X2 Do PutPixel(X,Y,Color);
End;

Procedure DrawPixelVLine(X,Y1,Y2,Color:Integer);
Var Y,T:Integer;
Begin
 If X<0 Then Exit;
 If X>=WBox Then Exit;
 If Y1>Y2 Then Begin T:=Y1; Y1:=Y2; Y2:=T; End;
 If Y1<0 Then Y1:=0;
 If Y2>=HBox Then Y2:=HBox-1;
 For Y:=Y1 To Y2 Do PutPixel(X,Y,Color);
End;

Procedure DrawGrid;
Var I,X,Y,StepT,StepX:Integer; TimeMs:Real; S:String;
Begin
 SetColor(Black);
 OutTextXY(PlotLeft,8,'Trace');
 OutTextXY(4,PlotTop,'ms');

 SetColor(LightGray);
 Rectangle(PlotLeft,PlotTop,PlotLeft+PlotW-1,PlotTop+PlotH-1);

 StepT:=NS Div 8;
 If StepT<1 Then StepT:=1;
 I:=0;
 While I<NS Do Begin
  If NS<=1 Then Y:=PlotTop Else Y:=PlotTop+Round(I*(PlotH-1)/(NS-1));
  DrawPixelHLine(PlotLeft,PlotLeft+PlotW-1,Y,LightGray);
  TimeMs:=I*DT/1000.0;
  SetColor(Black);
  S:=RealStr(TimeMs,0);
  OutTextXY(2,Y-4,S);
  I:=I+StepT;
 End;

 StepX:=NTr Div 8;
 If StepX<1 Then StepX:=1;
 I:=1;
 While I<=NTr Do Begin
  X:=PlotLeft+Round(I*PlotW/(NTr+1));
  DrawPixelVLine(X,PlotTop,PlotTop+PlotH-1,LightBlue);
  SetColor(Blue);
  S:=IntStr(I);
  OutTextXY(X-4,PlotTop+PlotH+6,S);
  I:=I+StepX;
 End;
End;

Procedure DrawGraphics;
Var X,Y,C:Integer; ClipVal:Real;
Begin
 InitializeGraphics;
 ClipVal:=ComputeClip;
 ClearDevice;
 For Y:=0 To PlotH-1 Do Begin
  For X:=0 To PlotW-1 Do Begin
   C:=GrayPixel(X,Y,ClipVal);
   If C<255 Then PutPixel(PlotLeft+X,PlotTop+Y,GrayToColor(C));
  End;
 End;
 DrawGrid;
 If Verbose<>0 Then Begin
  SetColor(Black);
  OutTextXY(8,8,'SUXWIGB - appuyez sur une touche');
  OutTextXY(8,24,'dt='+Chr(48+(DT Div 1000) Mod 10)+' ms');
 End;
 ReadKey;
 CloseGraph;
End;

Procedure FreeTraces;
Var T:Integer;
Begin
 For T:=1 To NTr Do Dispose(Trace[T]);
End;

BEGIN
 If(ParamStr(1)='/?')Or(ParamStr(1)='--help')Or(ParamStr(1)='-h')Or
   (ParamStr(1)='/h')Or(ParamStr(1)='/H')Then Begin
  Help;
  Halt;
 End;
 InitDefaults;
 ParseArgs;
 ReadSU;
 If NTr=0 Then Begin
  WriteLn('SUXWIGB: aucune trace SU recue.');
  Halt(1);
 End;
 DrawGraphics;
 FreeTraces;
END.
