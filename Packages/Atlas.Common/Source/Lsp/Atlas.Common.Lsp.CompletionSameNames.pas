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
    cInsertPrefix = 'prefix';
    cInsertPrefixAdd = 'prefixAdd';
    cInsertMove = 'move';
    cInsertAdd = 'add';
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
    begin
      Result := cInsertAdd;
    end
    else
    begin
      Result := cInsertPrefixAdd;
    end;
  end
  else if (AInsert = TCompletionSameNameInsert.Uses_) and AMovable then
  begin
    Result := cInsertMove;
  end
  else
  begin
    Result := cInsertPrefix;
  end;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Die Verweise aus AReferences zwischen AStart und AStop.</summary>
function ReferencesIn(const AReferences: TArray<TUsesReference>; const AStart, AStop: TTextPosition):
  TArray<TUsesReference>;
var
  mReference: TUsesReference;
begin
  Result := nil;
  for mReference in AReferences do
  begin
    if Before(AStart, mReference.Range.StartPos) and Before(mReference.Range.EndPos, AStop) then
    begin
      Result := Result + [mReference];
    end;
  end;
end;

/// <summary>Stellen von AUnitName (AOwn) und AActiveUnit (AActive) in AInside; -1 ohne. True, wenn beide
/// vorkommen.</summary>
function FindPair(const AInside: TArray<TUsesReference>; const AUnitName, AActiveUnit: string;
  const ANamespaces: TArray<string>; out AOwn, AActive: Integer): Boolean;
var
  mIndex: Integer;
begin
  AOwn := -1;
  AActive := -1;
  for mIndex := 0 to High(AInside) do
  begin
    if TUsesClauses.IsUsed([AInside[mIndex].Name], AUnitName, ANamespaces) then
    begin
      AOwn := mIndex;
    end
    else if TUsesClauses.IsUsed([AInside[mIndex].Name], AActiveUnit, ANamespaces) then
    begin
      AActive := mIndex;
    end;
  end;
  Result := (AOwn >= 0) and (AActive >= 0);
end;

/// <summary>Entfernt AInside[AOwn] samt Komma und hängt den Namen vor AStop an: hinter dem vorigen Namen bis zu
/// seinem Ende, als erster bis vor den nächsten.</summary>
function MoveEdits(const AInside: TArray<TUsesReference>; AOwn: Integer; const AStop: TTextPosition):
  TArray<TTextEdit>;
begin
  if AOwn > 0 then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(AInside[AOwn - 1].Range.EndPos, AInside[AOwn].Range.EndPos), '')];
  end
  else
  begin
    Result := [TTextEdit.Create(TTextRange.Create(AInside[AOwn].Range.StartPos, AInside[AOwn + 1].Range.StartPos),
      '')];
  end;
  Result := Result + [TTextEdit.Create(TTextRange.Create(AStop, AStop), ', ' + AInside[AOwn].Name)];
end;

class function TCompletionSameNames.MoveToEnd(const ATokens: TArray<TPascalToken>; const AUnitName,
  AActiveUnit: string; const ANamespaces: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mClause: TUsesClauseInfo;
  mReferences, mInside: TArray<TUsesReference>;
  mOwn, mActive: Integer;
  mStop: TTextPosition;
begin
  AEdits := nil;
  Result := False;
  mReferences := TUsesClauses.References(ATokens);
  for mClause in TUsesClauses.Clauses(ATokens) do
  begin
    mStop := ATokens[mClause.Semicolon].StartPos;
    if mClause.Plain then
    begin
      mInside := ReferencesIn(mReferences, ATokens[mClause.UsesIndex].EndPos, mStop);
      // Nur wenn die Variante vor der aktiven steht; sonst wäre sie schon die aktive.
      if FindPair(mInside, AUnitName, AActiveUnit, ANamespaces, mOwn, mActive) then
      begin
        Result := mOwn < mActive;
        if Result then
        begin
          AEdits := MoveEdits(mInside, mOwn, mStop);
        end;
        Exit;
      end;
    end;
  end;
end;

end.
