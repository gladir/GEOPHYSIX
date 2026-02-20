{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program MAGNETIC;

Var
 Latitude,Inclination:Real;
 Err:Word;

Function TAN(x:Real):Real;Begin
 If Cos(x)=0 Then Begin
  WriteLn('Erreur : tangente ind‚finie pour x = ', x:0:2);
  Halt; { Arrˆte le programme pour ‚viter une division par z‚ro }
 End;
 TAN:=Sin(x)/Cos(x);
End;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('MAGNETIC : Cette commande permet de calculer l''inclinaison ',
                     'du champ magn‚tique terrestre en fonction des ',
                     'coordonn‚es.');
  WriteLn;
  WriteLn('Syntaxe : MAGNETIC latitude');
  WriteLn;
  WriteLn(' latitude  Ce parametre permet d''indiquer la lattitude en degr‚s');
  Halt;
 End
  Else
 If ParamCount=1 Then Begin
  Val(ParamStr(1),latitude,Err);
 End
  Else
 Begin
  Write('Entrez la latitude (en degr‚s) : ');
  ReadLn(latitude);
 End;
 inclination := ArcTan(2*Tan(latitude * pi / 180)) * 180 / pi;
 WriteLn('Inclinaison magn‚tique : ', inclination:0:2, ' degr‚s');
END.