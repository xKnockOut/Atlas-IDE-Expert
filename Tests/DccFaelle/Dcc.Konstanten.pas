unit Dcc.Konstanten;

// #1328, Regel typed-constant-modified: typisierte Konstanten unter {$J+}
// (HtmlViewer, F19).

interface

procedure MitJ;
procedure MitWriteableConst;
procedure MitInclude;

implementation

{$J+}
procedure MitJ;
const
  cLetzter: Integer = 0;
begin
  cLetzter := 1; // TC1: {$J+}
end;
{$J-}

{$WRITEABLECONST ON}
procedure MitWriteableConst;
const
  cLetzter: Integer = 0;
begin
  cLetzter := 2; // TC2: {$WRITEABLECONST ON}
end;
{$WRITEABLECONST OFF}

{$I Dcc.Konstanten.inc}
procedure MitInclude;
const
  cLetzter: Integer = 0;
begin
  cLetzter := 3; // TC3: {$J+} aus einer Include-Datei
end;

end.
