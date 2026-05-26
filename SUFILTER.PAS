{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)

  SUFILTER - clone console de la commande sufilter de Seismic Unix.

  Cette version lit un signal texte sur stdin, un echantillon reel par ligne,
  puis ecrit le signal filtre sur stdout, un echantillon par ligne.

  Elle applique un filtre zero-phase en domaine frequentiel. La reponse en
  amplitude est definie par des points f= et amps=, avec une interpolation
  sine-squared entre deux points consecutifs, comme l'esprit de sufilter.
}

Program SUFILTER;

Const
 MaxSamples = 8192;
 MaxPoints  = 32;
 PiValue    = 3.1415926535897932385;

Type
 TRealArray = Array[1..MaxSamples] Of Real;
 PRealArray = ^TRealArray;

Var
 Data,OutData,Re,Im,FRe,FIm:PRealArray;
 Freq,Amp:Array[1..MaxPoints] Of Real;
 NFreq,N,NFFT,ReqNFFT:Integer;
 Dt:Real;

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

Function RealOf(S:String; Def:Real):Real;
Var R:Real; Code:Integer;
Begin
 Val(S,R,Code);
 If Code=0 Then RealOf:=R Else RealOf:=Def;
End;

Procedure Help;
Begin
 WriteLn('SUFILTER - Cette commande permet d''appliquer un filtre '+#133+' phase nulle ',
         'et '+#133+' variation sinuso'+#139+'dale carr'+#130+'e.');
 WriteLn;
 WriteLn('Syntaxe : SUFILTER <stdin >stdout [optional parameters]');
 WriteLn;
 WriteLn(' optional parameters:');
  WriteLn('  dt=valeur       Intervalle d''echantillonnage en secondes (defaut 0.004)');
 WriteLn('  nfft=valeur     Taille DFT avec zero-padding (defaut auto, min 256)');
 WriteLn('  f=f1,f2,...     Frequences des coins du filtre, en Hz');
 WriteLn('  amps=a1,a2,...  Amplitudes aux coins correspondants');
 WriteLn;
 WriteLn('Exemple : SUFILTER dt=0.004 f=5,10,40,50 amps=0,1,1,0 <in.txt >out.txt');
 WriteLn;
 WriteLn('Note : ce clone traite des echantillons texte, pas le format SU binaire.');
End;

Procedure InitDefaults;
Begin
 Dt:=0.004;
 ReqNFFT:=0;
 NFreq:=4;
 Freq[1]:=0.0;  Amp[1]:=0.0;
 Freq[2]:=5.0;  Amp[2]:=1.0;
 Freq[3]:=50.0; Amp[3]:=1.0;
 Freq[4]:=60.0; Amp[4]:=0.0;
End;

Function ParseList(S:String; Var A:Array Of Real):Integer;
Var I,Count,Code:Integer; Part:String; R:Real;
Begin
 Count:=0; Part:='';
 For I:=1 To Length(S)+1 Do Begin
  If (I>Length(S)) Or (S[I]=',') Then Begin
   If Part<>'' Then Begin
    Val(Part,R,Code);
    If (Code=0) And (Count<MaxPoints) Then Begin
     A[Count]:=R;
     Inc(Count);
    End;
   End;
   Part:='';
  End
   Else Part:=Part+S[I];
 End;
 ParseList:=Count;
End;

Procedure ParseArgs;
Var I,C:Integer; S,V:String; Tmp:Array[0..MaxPoints-1] Of Real;
Begin
 For I:=1 To ParamCount Do Begin
  S:=ParamStr(I);
  If StartsWith(S,'dt=') Then Dt:=RealOf(Copy(S,4,Length(S)-3),Dt)
   Else If StartsWith(S,'nfft=') Then ReqNFFT:=Trunc(RealOf(Copy(S,6,Length(S)-5),0))
   Else If StartsWith(S,'f=') Then Begin
    V:=Copy(S,3,Length(S)-2);
    C:=ParseList(V,Tmp);
    If C>0 Then Begin
     NFreq:=C;
     For C:=1 To NFreq Do Freq[C]:=Tmp[C-1];
    End;
   End
   Else If StartsWith(S,'amps=') Then Begin
    V:=Copy(S,6,Length(S)-5);
    C:=ParseList(V,Tmp);
    If C>0 Then Begin
     If C<NFreq Then NFreq:=C;
     For C:=1 To NFreq Do Amp[C]:=Tmp[C-1];
    End;
   End;
 End;
 If NFreq<1 Then InitDefaults;
End;

Procedure ChooseNFFT;
Begin
 If ReqNFFT>N Then NFFT:=ReqNFFT
  Else Begin
   NFFT:=1;
   While NFFT<N Do NFFT:=NFFT*2;
   If NFFT<256 Then NFFT:=256;
  End;
 If NFFT>MaxSamples Then NFFT:=MaxSamples;
 If NFFT<N Then NFFT:=N;
End;

Procedure ReadSamples;
Var S:String; V:Real; Code:Integer;
Begin
 N:=0;
 While Not Eof(Input) Do Begin
  ReadLn(S);
  If S<>'' Then Begin
   Val(S,V,Code);
   If Code=0 Then Begin
    If N<MaxSamples Then Begin
     Inc(N);
     Data^[N]:=V;
    End;
   End;
  End;
 End;
End;

Function FilterAmp(F:Real):Real;
Var I:Integer; X,W:Real;
Begin
 If NFreq<=0 Then Begin FilterAmp:=1.0; Exit; End;
 If F<=Freq[1] Then Begin FilterAmp:=Amp[1]; Exit; End;
 For I:=1 To NFreq-1 Do
  If (F>=Freq[I]) And (F<=Freq[I+1]) Then Begin
   If Freq[I+1]=Freq[I] Then X:=0.0 Else X:=(F-Freq[I])/(Freq[I+1]-Freq[I]);
   W:=Sqr(Sin(0.5*PiValue*X));
   FilterAmp:=Amp[I]+(Amp[I+1]-Amp[I])*W;
   Exit;
  End;
 FilterAmp:=Amp[NFreq];
End;

Procedure ForwardDFT;
Var K,J:Integer; Ang,C,S:Real;
Begin
 For K:=1 To NFFT Do Begin
  Re^[K]:=0.0; Im^[K]:=0.0;
  For J:=1 To NFFT Do Begin
   Ang:=-2.0*PiValue*(K-1)*(J-1)/NFFT;
   C:=Cos(Ang); S:=Sin(Ang);
   If J<=N Then Begin
    Re^[K]:=Re^[K]+Data^[J]*C;
    Im^[K]:=Im^[K]+Data^[J]*S;
   End;
  End;
 End;
End;

Procedure ApplyFilter;
Var K:Integer; F,A:Real;
Begin
 For K:=1 To NFFT Do Begin
  If K<=NFFT Div 2+1 Then F:=(K-1)/(NFFT*Dt)
   Else F:=(NFFT-K+1)/(NFFT*Dt);
  A:=FilterAmp(F);
  FRe^[K]:=Re^[K]*A;
  FIm^[K]:=Im^[K]*A;
 End;
End;

Procedure InverseDFT;
Var J,K:Integer; Ang,C,S,Sum:Real;
Begin
 For J:=1 To N Do Begin
  Sum:=0.0;
  For K:=1 To NFFT Do Begin
   Ang:=2.0*PiValue*(K-1)*(J-1)/NFFT;
   C:=Cos(Ang); S:=Sin(Ang);
   Sum:=Sum+FRe^[K]*C-FIm^[K]*S;
  End;
  OutData^[J]:=Sum/NFFT;
 End;
End;

Procedure WriteSamples;
Var I:Integer;
Begin
 For I:=1 To N Do WriteLn(OutData^[I]:0:8);
End;

Procedure AllocateBuffers;
Begin
 New(Data); New(OutData); New(Re); New(Im); New(FRe); New(FIm);
End;

Procedure FreeBuffers;
Begin
 Dispose(FIm); Dispose(FRe); Dispose(Im); Dispose(Re); Dispose(OutData); Dispose(Data);
End;

BEGIN
 If(ParamStr(1)='/?')Or(ParamStr(1)='--help')Or(ParamStr(1)='-h')Or
   (ParamStr(1)='/h')Or(ParamStr(1)='/H')Then Begin
  Help;
  Halt;
 End;
 InitDefaults;
 ParseArgs;
 AllocateBuffers;
 ReadSamples;
 If N>0 Then Begin
  ChooseNFFT;
  ForwardDFT;
  ApplyFilter;
  InverseDFT;
  WriteSamples;
 End;
 FreeBuffers;
END.
