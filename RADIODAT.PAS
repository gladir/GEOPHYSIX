{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program RADIODAT;

Const
 LAMBDA = 1.42e-11; { Constante de d‚sint‚gration de l'Uranium-238 (1/s) }

Var
 Parent,Daughter,Ratio,Age:Real;
 Err:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('RADIODAT : Cette commande permet de calculer l''ƒge d''une roche ',
                      'par la loi de d‚sint‚gration radioactive.');
  WriteLn;
  WriteLn('Syntaxe : RADIODAT parent daughter');
  WriteLn;
  WriteLn(' parent   Ce paramŠtre permet d''indiquer le nombre d''atomes parents restants');
  WriteLn(' daughter Ce paramŠtre permet d''indiquer le nombre d''atomes fils produits');
  Halt;
 End
  Else
 If ParamCount=2 Then Begin
  Val(ParamStr(1),Parent,Err);
  Val(ParamStr(2),Daughter,Err);
 End
  Else
 Begin
  Write('Nombre d''atomes parents restants : ');
  Readln(Parent);
  Write('Nombre d''atomes fils produits : ');
  Readln(Daughter);
 End;
 Ratio:=Daughter / Parent;
 Age := ln(1 + ratio) / LAMBDA / (365.25 * 24 * 3600 * 1e6); { en millions d'ann‚es }
 WriteLn('Age estim‚ : ', age:0:2, ' millions d''ann‚es');
END.