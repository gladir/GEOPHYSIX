{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)

  SUPLANE - clone console de la commande suplane de Seismic Unix.

  Cette commande cree un jeu de traces SU synthetique contenant jusqu'a
  trois evenements plans. La sortie est un flux SU binaire sur stdout:

    SUPLANE ntr=120 nt=256 dt=0.004 > plane.su

  Les parametres suivent l'esprit de suplane:
    npl=3, nt=64, ntr=32, taper=0, offset=400, dt=0.004
    dip1=0 len1=3*ntr/4 ct1=nt/2 cx1=ntr/2
    dip2=4 len2=3*ntr/4 ct2=nt/2 cx2=ntr/2
    dip3=-4 len3=3*ntr/4 ct3=nt/2 cx3=ntr/2

  dip est exprime en millisecondes par trace; ct/cx indiquent le pivot
  de l'evenement en echantillon et trace.
}

Program SUPLANE;

{$N+}

Const
 MaxSamples = 8192;
 MaxPlanes = 3;
 PiValue = 3.1415926535897932385;

Type
 TSampleArray = Array[1..MaxSamples] Of Single;
 PSampleArray = ^TSampleArray;
 TTraceHeader = Array[1..240] Of Byte;

Var
 OutF:File;
 Data:PSampleArray;
 NPl,NT,NTr,Taper,Offset:Integer;
 DT:Real;
 Dip:Array[1..MaxPlanes] Of Real;
 LenP,CT,CX:Array[1..MaxPlanes] Of Integer;

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
 WriteLn('SUPLANE - Cette commande permet de cr'+#130+'er un fichier de ',
         'donn'+#130+'es de d'+#130+'calage commun avec jusqu'''+#133+
         ' 3 plans.');
 WriteLn;
 WriteLn('Syntaxe : SUPLANE [parametres optionnels] >stdout');
 WriteLn;
 WriteLn(' parametres optionnels:');
 WriteLn('  npl=3       Nombre de plans, maximum 3');
 WriteLn('  nt=64       Nombre d'''+#130+'chantillons par trace');
 WriteLn('  ntr=32      Nombre de traces');
 WriteLn('  taper=0     0=sans taper, 1=taper aux extremites des plans');
 WriteLn('  offset=400  Offset inscrit dans l''en-tete SU');
 WriteLn('  dt=0.004    Intervalle d'''+#130+'chantillonnage en secondes');
 WriteLn('  dip1=0      Pente du plan 1 en ms/trace');
 WriteLn('  len1=...    Extension horizontale du plan 1 en traces');
 WriteLn('  ct1=...     Echantillon pivot du plan 1');
 WriteLn('  cx1=...     Trace pivot du plan 1');
 WriteLn('  dip2,len2,ct2,cx2 et dip3,len3,ct3,cx3 sont aussi acceptes.');
 WriteLn;
 WriteLn('Exemple : SUPLANE ntr=120 nt=256 dt=0.004 > plane.su');
End;

Procedure InitDefaults;
Var I:Integer;
Begin
 NPl:=3; NT:=64; NTr:=32; Taper:=0; Offset:=400; DT:=0.004;
 For I:=1 To MaxPlanes Do Begin
  Dip[I]:=0.0;
  LenP[I]:=3*NTr Div 4;
  CT[I]:=NT Div 2;
  CX[I]:=NTr Div 2;
 End;
 Dip[1]:=0.0; Dip[2]:=4.0; Dip[3]:=-4.0;
End;

Procedure ParseArgs;
Var I,P:Integer; S,V:String;
Begin
 For I:=1 To ParamCount Do Begin
  S:=ParamStr(I);
  If StartsWith(S,'npl=') Then NPl:=IntOf(Copy(S,5,Length(S)-4),NPl)
   Else If StartsWith(S,'nt=') Then NT:=IntOf(Copy(S,4,Length(S)-3),NT)
   Else If StartsWith(S,'ntr=') Then NTr:=IntOf(Copy(S,5,Length(S)-4),NTr)
   Else If StartsWith(S,'taper=') Then Taper:=IntOf(Copy(S,7,Length(S)-6),Taper)
   Else If StartsWith(S,'offset=') Then Offset:=IntOf(Copy(S,8,Length(S)-7),Offset)
   Else If StartsWith(S,'dt=') Then DT:=RealOf(Copy(S,4,Length(S)-3),DT)
   Else Begin
    For P:=1 To MaxPlanes Do Begin
     V:=Chr(Ord('0')+P);
     If StartsWith(S,'dip'+V+'=') Then Dip[P]:=RealOf(Copy(S,6,Length(S)-5),Dip[P]);
     If StartsWith(S,'len'+V+'=') Then LenP[P]:=IntOf(Copy(S,6,Length(S)-5),LenP[P]);
     If StartsWith(S,'ct'+V+'=') Then CT[P]:=IntOf(Copy(S,5,Length(S)-4),CT[P]);
     If StartsWith(S,'cx'+V+'=') Then CX[P]:=IntOf(Copy(S,5,Length(S)-4),CX[P]);
    End;
   End;
 End;
 If NPl<1 Then NPl:=1;
 If NPl>MaxPlanes Then NPl:=MaxPlanes;
 If NT<1 Then NT:=64;
 If NT>MaxSamples Then NT:=MaxSamples;
 If NTr<1 Then NTr:=32;
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
 For I:=1 To 240 Do H[I]:=0;
End;

Procedure MakeHeader(TraceNo:Integer; Var H:TTraceHeader);
Var DTus:LongInt;
Begin
 ZeroHeader(H);
 DTus:=Trunc(DT*1000000.0+0.5);
 PutLE32(H,1,TraceNo);
 PutLE32(H,5,TraceNo);
 PutLE16(H,29,1);
 PutLE32(H,37,Offset);
 PutLE16(H,115,NT);
 PutLE16(H,117,DTus);
 PutLE32(H,181,TraceNo);
 PutLE32(H,185,1);
End;

Function Ricker(X:Real):Real;
Var A:Real;
Begin
 A:=0.45*X;
 Ricker:=(1.0-2.0*A*A)*Exp(-A*A);
End;

Function PlaneScale(Plane,TraceNo:Integer):Real;
Var HalfLen,Dist:Real;
Begin
 HalfLen:=LenP[Plane]/2.0;
 If HalfLen<1.0 Then Begin PlaneScale:=0.0; Exit; End;
 Dist:=Abs(TraceNo-CX[Plane]);
 If Dist>HalfLen Then Begin PlaneScale:=0.0; Exit; End;
 If Taper=0 Then PlaneScale:=1.0
  Else PlaneScale:=Sqr(Sin(PiValue*(HalfLen-Dist)/(2.0*HalfLen)));
End;

Procedure MakeTrace(TraceNo:Integer);
Var I,P:Integer; Center,Scale,X:Real;
Begin
 For I:=1 To NT Do Data^[I]:=0.0;
 For P:=1 To NPl Do Begin
  Scale:=PlaneScale(P,TraceNo);
  If Scale<>0.0 Then Begin
   Center:=CT[P]+((TraceNo-CX[P])*Dip[P])/(DT*1000.0);
   For I:=1 To NT Do Begin
    X:=I-Center;
    If Abs(X)<=10.0 Then Data^[I]:=Data^[I]+Scale*Ricker(X);
   End;
  End;
 End;
End;

Procedure WriteTrace(TraceNo:Integer);
Var H:TTraceHeader; I:Integer;
Begin
 MakeHeader(TraceNo,H);
 BlockWrite(OutF,H,240);
 For I:=1 To NT Do WriteFloatLE(Data^[I]);
End;

Var Tr:Integer;

BEGIN
 If(ParamStr(1)='/?')Or(ParamStr(1)='--help')Or(ParamStr(1)='-h')Or
   (ParamStr(1)='/h')Or(ParamStr(1)='/H')Then Begin
  Help;
  Halt;
 End;
 InitDefaults;
 ParseArgs;
 New(Data);
 Assign(OutF,''); Rewrite(OutF,1);
 For Tr:=1 To NTr Do Begin
  MakeTrace(Tr);
  WriteTrace(Tr);
 End;
 Close(OutF);
 Dispose(Data);
END.
