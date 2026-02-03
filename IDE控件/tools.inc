function SetDirSeparatorsEx( FileName : String):String;
Var I : longint;

begin
  Result:=FileName;
  For I:=1 to Length(FileName) do
  begin
    if (FileName[I]='/') or (FileName[I]='\') then
      FileName[i]:=DirectorySeparator;
  end;
  Result:=FileName;
end;
