unit Atlas.Common.Lsp.CompletionSameNames;

// Gleiche Namen aus verschiedenen Units (#475, ARG-077), mit completion.sameNameVariants:
// - Deklarieren mehrere Units einen Namen, steht die Variante, die der Compiler nach den uses wählt (letzte Unit
//   gewinnt), zuerst mit „aktiv“; die übrigen folgen mit ihrer Unit, auch aus nicht eingebundenen Units.
// - Übernahme einer nicht aktiven Variante nach completion.sameNameInsert: prefix setzt den Unit-Präfix davor
//   (bei nicht eingebundener Unit kommt sie zusätzlich in die uses), uses verschiebt die Unit in ihrer
//   uses-Liste hinter die aktive bzw. ergänzt sie. Geht das Verschieben nicht (andere Liste, Direktiven in der
//   Liste), gilt der Präfix.
// - FireMonkey-Units (FMX.*) bleiben ohne completion.showFmxUnits ausgeblendet; die Fußzeile nennt sie.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract;

type
  TCompletionSameNames = class
  public const
    InsertPrefix = 'prefix';
    InsertPrefixAdd = 'prefixAdd';
    InsertMove = 'move';
    InsertAdd = 'add';
  public
    /// <summary>FireMonkey-Unit (FMX oder FMX.*)?</summary>
    class function IsFmx(const AUnitName: string): Boolean; static;
    /// <summary>Was Enter mit einer nicht aktiven Variante tut: AUsed = ihre Unit ist eingebunden, AMovable =
    /// sie steht mit der aktiven in derselben schlichten uses-Liste vor ihr.</summary>
    class function InsertMode(AInsert: TCompletionSameNameInsert; AUsed, AMovable: Boolean): string; static;
    /// <summary>Edits, die AUnitName in ihrer uses-Liste ans Ende setzen, wenn AActiveUnit in derselben
    /// schlichten Liste weiter hinten steht; False sonst. Namen auch ohne Namespace (Graphics für
    /// Vcl.Graphics über ANamespaces).</summary>
    class function MoveToEnd(const ATokens: TArray<TPascalToken>; const AUnitName, AActiveUnit: string;
      const ANamespaces: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Editing.UsesClause;

class function TCompletionSameNames.IsFmx(const AUnitName: string): Boolean;
begin
  Result := SameText(AUnitName, 'FMX') or StartsText('FMX.', AUnitName);
end;

class function TCompletionSameNames.InsertMode(AInsert: TCompletionSameNameInsert; AUsed, AMovable: Boolean): string;
begin
  if not AUsed then
  begin
    if AInsert = TCompletionSameNameInsert.Uses_ then
      Result := InsertAdd
    else
      Result := InsertPrefixAdd;
  end
  else if (AInsert = TCompletionSameNameInsert.Uses_) and AMovable then
    Result := InsertMove
  else
    Result := InsertPrefix;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

class function TCompletionSameNames.MoveToEnd(const ATokens: TArray<TPascalToken>; const AUnitName,
  AActiveUnit: string; const ANamespaces: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  Clause: TUsesClauseInfo;
  References, Inside: TArray<TUsesReference>;
  Reference: TUsesReference;
  Index, Own, Active: Integer;
  Start, Stop: TTextPosition;
begin
  AEdits := nil;
  Result := False;
  References := TUsesClauses.References(ATokens);
  for Clause in TUsesClauses.Clauses(ATokens) do
  begin
    if not Clause.Plain then
      Continue;
    Start := ATokens[Clause.UsesIndex].EndPos;
    Stop := ATokens[Clause.Semicolon].StartPos;
    Inside := nil;
    for Reference in References do
      if Before(Start, Reference.Range.StartPos) and Before(Reference.Range.EndPos, Stop) then
        Inside := Inside + [Reference];
    Own := -1;
    Active := -1;
    for Index := 0 to High(Inside) do
      if TUsesClauses.IsUsed([Inside[Index].Name], AUnitName, ANamespaces) then
        Own := Index
      else if TUsesClauses.IsUsed([Inside[Index].Name], AActiveUnit, ANamespaces) then
        Active := Index;
    if (Own < 0) or (Active < 0) then
      Continue;
    // Nur wenn die Variante vor der aktiven steht; sonst wäre sie schon die aktive.
    if Own > Active then
      Exit;
    // Entfernen samt Komma: hinter dem vorigen Namen bis zu ihrem Ende, als erster bis vor den nächsten.
    if Own > 0 then
      AEdits := [TTextEdit.Create(TTextRange.Create(Inside[Own - 1].Range.EndPos, Inside[Own].Range.EndPos), '')]
    else
      AEdits := [TTextEdit.Create(TTextRange.Create(Inside[Own].Range.StartPos, Inside[Own + 1].Range.StartPos), '')];
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Stop, Stop), ', ' + Inside[Own].Name)];
    Exit(True);
  end;
end;

end.
