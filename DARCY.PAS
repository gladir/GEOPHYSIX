{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/geophysix)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DARCY;

Var
 k,area,dp,Len,flow:Real;
 Err:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('DARCY : Cette commande permet de calculer le d‚bit d''un ',
                    'fluide … travers un sol perm‚able selon la Loi de ',
                    'Darcy.');
  WriteLn;
  WriteLn('Syntaxe : DARCY k Area dp Len');
  WriteLn;
  WriteLn(' k    Ce paramŠtre permet d''indiquer la perm‚abilit‚ du sol (mý)');
  WriteLn(' Area Ce paramŠtre permet d''indiquer la section transversale (mý)');
  WriteLn(' dp   Ce paramŠtre permet d''indiquer la diff‚rence de pression (Pa)');
  WriteLn(' Len  Ce paramŠtre permet d''indiquer la longueur de l''‚chantillon (m)');
  Halt;
 End
  Else
 If ParamCount=4 Then Begin
  Val(ParamStr(1),k,Err);
  Val(ParamStr(2),Area,Err);
  Val(ParamStr(3),dp,Err);
  Val(ParamStr(4),Len,Err);
 End
  Else
 Begin
  Write('Perm‚abilit‚ du sol (mý) : ');
  ReadLn(k);
  Write('Section transversale (mý) : ');
  ReadLn(Area);
  Write('Diff‚rence de pression (Pa) : ');
  ReadLn(dp);
  Write('Longueur de l''‚chantillon (m) : ');
  ReadLn(Len);
 End;
 Flow := k*Area*DP/Len;
 Writeln('D‚bit du fluide : ', flow:0:5, ' m au cube/s');
END.