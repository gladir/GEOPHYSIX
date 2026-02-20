{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program BOUGUER;

Const
 G = 9.81;          { Gravit‚ moyenne en m/s au carr‚ }
 RHO = 2670;        { Densit‚ moyenne des roches en kg/m au cube }
 GAMA = 0.0003086;  { Correction de Bouguer en mGal/m }

Var
 g_measured,Altitude,Anomaly:Real;
 Err:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('BOUGUER : Cette commande permet de calculer l''anomalie ',
                    'de Bouguer.');
  WriteLn;
  WriteLn('Syntaxe : BOUGUER gravite altitude');
  WriteLn;
  WriteLn(' gravite  Ce parametre permet d''indiquer la gravit‚ mesur‚e');
  WriteLn(' altitude Ce parametre permet d''indiquer l''altitude');
  Halt;
 End
  Else
 If ParamCount=2 Then Begin
  Val(ParamStr(1),g_measured,Err);
  Val(ParamStr(2),altitude,Err);
 End
  Else
 Begin
  Write('Entrez la gravit‚ mesur‚e (mGal): ');
  ReadLn(g_measured);
  Write('Entrez l''altitude (m): ');
  ReadLn(altitude);
 End;
 Anomaly := g_measured - G + GAMA * RHO * altitude;
 Writeln('Anomalie de Bouguer: ', anomaly:0:3, ' mGal');
END.