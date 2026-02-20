{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DEEPTEMP;

Const
 GRADIENT = 0.03; { Gradient g‚othermique moyen en øC/m }

Var
 Depth,Temp_surface,Temp_depth:Real;
 Err:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('DEEPTEMP : Cette commande permet de calculer la temp‚rature ',
                      'en fonction de la profondeur en utilisant un ',
                      'gradient constant (Gradiant G‚othermique).');
  WriteLn;
  WriteLn('Syntaxe : DEEPTEMP temp_Surface depth');
  WriteLn;
  WriteLn(' temp_Surface Ce parametre permet d''indiquer la temp‚rature de surface (øC)');
  WriteLn(' depth        Ce parametre permet d''indiquer la profondeur (m)');
  Halt;
 End
  Else
 If ParamCount=2 Then Begin
  Val(ParamStr(1),temp_Surface,Err);
  Val(ParamStr(2),depth,Err);
 End
  Else
 Begin
  Write('Temp‚rature de surface (øC) : ');
  ReadLn(temp_surface);
  Write('Profondeur (m) : ');
  ReadLn(depth);
 End;
 Temp_Depth := temp_surface + GRADIENT * Depth;
 WriteLn('Temp‚rature … ',depth:0:1,' m : ',temp_depth:0:2,' øC');
END.