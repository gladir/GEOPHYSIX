{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ATTEN;

Const
 Q=100;  { Facteur de qualit‚ (‚nergie dissip‚e) }

Var
 amplitude0,distance,amplitude:Real;
 Err:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('ATTEN : Cette commande permet de calculer l''att‚nuation d''une ',
                  'onde sismique en fonction de la distance.');
  WriteLn;
  WriteLn('Syntaxe : ATTEN amplitude0 distance');
  WriteLn;
  WriteLn(' amplitude0  Ce parametre permet d''indiquer l''amplitude initiale');
  WriteLn(' distance    Ce parametre permet d''indiquer la distance parcourue (km)');
  Halt;
 End
  Else
 If ParamCount=2 Then Begin
  Val(ParamStr(1),amplitude0,Err);
  Val(ParamStr(2),distance,Err);
 End
  Else
 Begin
  Write('Amplitude initiale : ');
  ReadLn(amplitude0);
  Write('Distance parcourue (km) : ');
  ReadLn(distance);
 End;
 Amplitude:=Amplitude0*Exp(-distance/Q);
 WriteLn('Amplitude att‚nu‚e : ', amplitude:0:5);
END.