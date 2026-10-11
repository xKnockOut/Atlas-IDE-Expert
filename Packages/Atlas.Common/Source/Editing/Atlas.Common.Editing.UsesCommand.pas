unit Atlas.Common.Editing.UsesCommand;

// Schnellbefehl /uses (#254), ohne Protokollbezug.
//
// Eine Zeile "/uses System.SysUtils, Vcl.Forms" (Semikolon erlaubt) wird nach
// Enter gelöscht und die Units kommen über TUsesClauses ins uses des
// Abschnitts, in dem die Zeile stand. Schon eingebundene Units entfallen.
// Die Befehlszeile wird vor dem Zerlegen durch Leerzeichen ersetzt, damit ihr
// "uses" nicht als uses-Liste gilt und alle Positionen gleich bleiben.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract;

type
  TUsesCommand = class
  public
    /// <summary>Unit-Namen aus einer Befehlszeile; False, wenn die Zeile kein /uses ist.</summary>
    class function Parse(const ALine: string; out AUnits: TArray<string>): Boolean; static;
    /// <summary>Edits nach Enter in Zeile APosition.Line: Befehlszeile darüber löschen und
    /// Units eintragen. False, wenn die Zeile darüber kein /uses ist.</summary>
    class function AfterEnter(const AText: string; const APosition: TTextPosition;
      const ANamespaces: TArray<string>; out AEdits: TArray<TRuleEdit>): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause;

function IsUnitName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := AName <> '';
  for Index := 1 to Length(AName) do
    if not CharInSet(AName[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
      Exit(False);
  Result := Result and not CharInSet(AName[1], ['0'..'9', '.']) and (AName[Length(AName)] <> '.');
end;

class function TUsesCommand.Parse(const ALine: string; out AUnits: TArray<string>): Boolean;
var
  Rest, Name: string;
begin
  AUnits := nil;
  Rest := Trim(ALine);
  if not Rest.StartsWith('/uses ', True) then
    Exit(False);
  Rest := Trim(Copy(Rest, 7, MaxInt));
  if Rest.EndsWith(';') then
    Rest := Trim(Copy(Rest, 1, Length(Rest) - 1));
  for Name in Rest.Split([',']) do
  begin
    if not IsUnitName(Trim(Name)) then
      Exit(False);
    AUnits := AUnits + [Trim(Name)];
  end;
  Result := Length(AUnits) > 0;
end;

class function TUsesCommand.AfterEnter(const AText: string; const APosition: TTextPosition;
  const ANamespaces: TArray<string>; out AEdits: TArray<TRuleEdit>): Boolean;
var
  Lines, Units, Used, Missing: TArray<string>;
  Line, Offset, Index: Integer;
  LineBreak, Blanked, Name: string;
  Tokens: TArray<TPascalToken>;
  Edit: TRuleEdit;
begin
  AEdits := nil;
  Line := APosition.Line - 1;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10
  else
    LineBreak := #10;
  Lines := AText.Split([LineBreak]);
  if (Line < 0) or (Line >= High(Lines) + 1) or not Parse(Lines[Line], Units) then
    Exit(False);
  Offset := 0;
  for Index := 0 to Line - 1 do
    Inc(Offset, Length(Lines[Index]) + Length(LineBreak));
  Blanked := Copy(AText, 1, Offset) + StringOfChar(' ', Length(Lines[Line])) +
    Copy(AText, Offset + Length(Lines[Line]) + 1, MaxInt);
  Tokens := TPascalLexer.Tokenize(Blanked);
  Used := TUsesClauses.UsedUnits(Tokens);
  Missing := nil;
  for Name in Units do
    if not TUsesClauses.IsUsed(Used + Missing, Name, ANamespaces) then
      Missing := Missing + [Name];
  // Die Befehlszeile samt Zeilenende verschwindet in jedem Fall.
  AEdits := [TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(Line, 0), TTextPosition.Create(Line + 1, 0)), '')];
  if (Length(Missing) > 0) and
    TUsesClauses.AddUnit(Tokens, Offset, string.Join(', ', Missing), LineBreak, Edit) then
    AEdits := [Edit] + AEdits;
  Result := True;
end;

end.
