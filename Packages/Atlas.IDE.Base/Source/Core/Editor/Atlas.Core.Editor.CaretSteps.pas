unit Atlas.Core.Editor.CaretSteps;

// Eigene Schritte bei mehreren Einfügemarken (#589) für Rückgängig und Wiederholen der IDE, ohne Open Tools API.
// Jeder Schritt merkt sich Text und Marken davor und danach. Steht der Text nach Rückgängig bzw. Wiederholen der
// IDE auf dem Stand vor bzw. nach einem eigenen Schritt, kehren dessen Marken zurück. Ein neuer Schritt verwirft,
// was danach wiederholt werden könnte; gemerkt werden höchstens cLimit Schritte.
// Dazu die Umrechnung der Marken in Bereiche (Umschließen, #672) und zurück.

interface

uses
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.MultiCursor;

type
  /// <summary>Ein eigener Schritt: Text und Marken davor und danach.</summary>
  TAtlasCaretStep = record
    Before: string;
    After: string;
    BeforeCarets: TAtlasCarets;
    AfterCarets: TAtlasCarets;
  end;

  TAtlasCaretSteps = record
  public const
    /// <summary>So viele eigene Schritte merkt sich Atlas.</summary>
    cLimit = 20;
  private
    FSteps: TArray<TAtlasCaretStep>;
    FIndex: Integer;
  public
    /// <summary>Alle Schritte vergessen.</summary>
    procedure Clear;
    /// <summary>Neuer eigener Schritt von ABefore nach AAfter.</summary>
    procedure Add(const ABefore, AAfter: string; const ABeforeCarets, AAfterCarets: TAtlasCarets);
    /// <summary>Steht AText auf dem Stand vor dem letzten bzw. nach dem nächsten eigenen Schritt (Rückgängig bzw.
    /// Wiederholen), stehen in ACarets dessen Marken (eigene Kopie), und der Schritt gilt als zurückgenommen bzw.
    /// wiederholt. Sonst False.</summary>
    function Recall(const AText: string; out ACarets: TAtlasCarets): Boolean;
    /// <summary>Gemerkte Schritte.</summary>
    function Count: Integer;
    /// <summary>Schritte, die gerade gelten (der Rest lässt sich wiederholen).</summary>
    property Index: Integer read FIndex;
  end;

  TAtlasCaretRanges = record
  public
    /// <summary>Bereiche der Marken (Anfang vor Ende).</summary>
    class function RangesOf(const ACarets: TAtlasCarets): TArray<TLspRange>; static;
    /// <summary>Marken aus Bereichen (Anker am Anfang, Cursor am Ende).</summary>
    class function CaretsOf(const ARanges: TArray<TLspRange>): TAtlasCarets; static;
  end;

implementation

{ TAtlasCaretSteps }

procedure TAtlasCaretSteps.Clear;
begin
  FSteps := nil;
  FIndex := 0;
end;

procedure TAtlasCaretSteps.Add(const ABefore, AAfter: string; const ABeforeCarets, AAfterCarets: TAtlasCarets);
var
  mStep: TAtlasCaretStep;
begin
  // Ein neuer Schritt verwirft, was nach dem aktuellen wiederholt werden könnte.
  SetLength(FSteps, FIndex);
  mStep.Before := ABefore;
  mStep.After := AAfter;
  mStep.BeforeCarets := Copy(ABeforeCarets);
  mStep.AfterCarets := Copy(AAfterCarets);
  FSteps := FSteps + [mStep];
  if Length(FSteps) > cLimit then
  begin
    Delete(FSteps, 0, 1);
  end;
  FIndex := Length(FSteps);
end;

function TAtlasCaretSteps.Recall(const AText: string; out ACarets: TAtlasCarets): Boolean;
begin
  ACarets := nil;
  Result := (FIndex > 0) and (AText = FSteps[FIndex - 1].Before);
  if Result then
  begin
    ACarets := Copy(FSteps[FIndex - 1].BeforeCarets);
    Dec(FIndex);
    Exit;
  end;
  Result := (FIndex < Length(FSteps)) and (AText = FSteps[FIndex].After);
  if Result then
  begin
    ACarets := Copy(FSteps[FIndex].AfterCarets);
    Inc(FIndex);
  end;
end;

function TAtlasCaretSteps.Count: Integer;
begin
  Result := Length(FSteps);
end;

{ TAtlasCaretRanges }

class function TAtlasCaretRanges.RangesOf(const ACarets: TAtlasCarets): TArray<TLspRange>;
var
  mIndex, mStartLine, mStartCharacter, mEndLine, mEndCharacter: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ACarets));
  for mIndex := 0 to High(ACarets) do
  begin
    ACarets[mIndex].Bounds(mStartLine, mStartCharacter, mEndLine, mEndCharacter);
    Result[mIndex] := TLspRange.Create(mStartLine, mStartCharacter, mEndLine, mEndCharacter);
  end;
end;

class function TAtlasCaretRanges.CaretsOf(const ARanges: TArray<TLspRange>): TAtlasCarets;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ARanges));
  for mIndex := 0 to High(ARanges) do
  begin
    Result[mIndex] := TAtlasCaret.Range(ARanges[mIndex].StartPos.Line, ARanges[mIndex].StartPos.Character,
      ARanges[mIndex].EndPos.Line, ARanges[mIndex].EndPos.Character);
  end;
end;

end.
