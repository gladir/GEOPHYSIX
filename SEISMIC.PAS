{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program SEISMIC;

Var
 rho,k,mu,v_p,v_s:Real;
 Err:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('SEISMIC : Cette commande permet de calculer la vitesse ',
                    'des ondes P et S en fonction de la densit‚ ',
                    'et des modules ‚lastiques.');
  WriteLn;
  WriteLn('Syntaxe : SEISMIC rho k mu');
  WriteLn;
  WriteLn(' rho  Ce paramŠtre permet d''indiquer la densit‚ (kg/m au cube)');
  WriteLn(' k    Ce parametre permet d''indiquer le module de compressibilit‚ (Pa)');
  WriteLN(' mu   Ce paramŠtre permet d''indiquer le module de cisaillement (Pa');
  Halt;
 End
  Else
 If ParamCount=3 Then Begin
  Val(ParamStr(1),rho,Err);
  Val(ParamStr(2),k,Err);
  Val(ParamStr(3),mu,Err);
 End
  Else
 Begin
  Write('Entrez la densit‚ (kg/m au cube) : ');
  ReadLn(rho);
  Write('Entrez le module de compressibilit‚ (Pa) : ');
  ReadLn(k);
  Write('Entrez le module de cisaillement (Pa) : ');
  ReadLn(mu);
 End;
 v_p := Sqrt((k + 4/3 * mu) / rho);
 v_s := Sqrt(mu / rho);
 Writeln('Vitesse de l''onde P : ', v_p:0:2, ' m/s');
 Writeln('Vitesse de l''onde S : ', v_s:0:2, ' m/s');
END.
