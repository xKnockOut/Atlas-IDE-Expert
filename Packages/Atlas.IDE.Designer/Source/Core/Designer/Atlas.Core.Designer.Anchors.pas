unit Atlas.Core.Designer.Anchors;

// Anchors im Designer vorschlagen (#727), ohne VCL und Windows. Je Parent
// mit seiner Clientgröße; „am Rand“ heißt höchstens AEdge Pixel Abstand.
// - Füllende Klassen (designer.suggestAnchors.fillClasses): alle vier.
// - Links, rechts und unten am Rand: links, rechts, unten.
// - Links und rechts am Rand: links, oben, rechts.
// - Rechts und unten am Rand: rechts, unten; nur rechts: oben, rechts; nur
//   unten: links, unten. Sonst die Vorgabe links, oben.
// - Align <> alNone: übergangen („durch Align geregelt“). Vorhandene, von
//   links/oben abweichende Anchors bleiben mit AKeepExisting („vorhanden“).
// - Reihe (gleiche Oberkante ± cRowTolerance, Lücken bis AEdge): alle
//   bekommen die Anchors der äußersten; rechts verankert zählt die rechte,
//   sonst die linke.
// - Ein Label mit FocusControl folgt den senkrechten Anchors seines Felds,
//   waagerecht nur links.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasAnchorSide = (Left, Top, Right, Bottom);
  TAtlasAnchorReason = (Aligned, Existing, Fill, WideBottom, Wide, BottomRight, Right, Bottom, Row, FollowsField,
    Default);
{$SCOPEDENUMS OFF}
  TAtlasAnchorSet = set of TAtlasAnchorSide;

  TAtlasAnchorItem = record
    Name: string;
    Bounds: TRect;
    Aligned: Boolean;
    Fill: Boolean;
    Existing: TAtlasAnchorSet;
    /// <summary>Name des Felds bei einem Label mit FocusControl; leer ohne.</summary>
    FocusOf: string;
    class function Create(const AName: string; const ABounds: TRect; AAligned, AFill: Boolean;
      AExisting: TAtlasAnchorSet; const AFocusOf: string): TAtlasAnchorItem; static;
  end;

  TAtlasAnchorSuggestion = record
    Anchors: TAtlasAnchorSet;
    Reason: TAtlasAnchorReason;
    /// <summary>Weicht vom vorhandenen Wert ab (und wird damit angeboten)?</summary>
    Changed: Boolean;
  end;

  TAtlasAnchorSuggest = class
  public const
    cDefault = [TAtlasAnchorSide.Left, TAtlasAnchorSide.Top];
    cAll = [TAtlasAnchorSide.Left, TAtlasAnchorSide.Top, TAtlasAnchorSide.Right,
      TAtlasAnchorSide.Bottom];
    cRowTolerance = 4;
  public
    class function Suggest(const AItems: TArray<TAtlasAnchorItem>; const AClient: TSize; AEdge: Integer;
      AKeepExisting: Boolean): TArray<TAtlasAnchorSuggestion>; static;
    /// <summary>„L T R B“ mit „-“ für fehlende Seiten.</summary>
    class function Text(AAnchors: TAtlasAnchorSet): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasAnchorItem }

class function TAtlasAnchorItem.Create(const AName: string; const ABounds: TRect; AAligned, AFill: Boolean;
  AExisting: TAtlasAnchorSet; const AFocusOf: string): TAtlasAnchorItem;
begin
  Result.Name := AName;
  Result.Bounds := ABounds;
  Result.Aligned := AAligned;
  Result.Fill := AFill;
  Result.Existing := AExisting;
  Result.FocusOf := AFocusOf;
end;

{ TAtlasAnchorSuggest }

function Suggestion(AAnchors: TAtlasAnchorSet; AReason: TAtlasAnchorReason): TAtlasAnchorSuggestion;
begin
  Result.Anchors := AAnchors;
  Result.Reason := AReason;
  Result.Changed := False;
end;

/// <summary>Vorschlag nach den Rändern.</summary>
function ByEdges(const AItem: TAtlasAnchorItem; const AClient: TSize; AEdge: Integer): TAtlasAnchorSuggestion;
var
  mLeft, mRight, mBottom: Boolean;
begin
  mLeft := AItem.Bounds.Left <= AEdge;
  mRight := AClient.cx - AItem.Bounds.Right <= AEdge;
  mBottom := AClient.cy - AItem.Bounds.Bottom <= AEdge;
  if AItem.Fill then
  begin
    Result := Suggestion(TAtlasAnchorSuggest.cAll, TAtlasAnchorReason.Fill);
  end
  else if mLeft and mRight and mBottom then
  begin
    Result := Suggestion([TAtlasAnchorSide.Left, TAtlasAnchorSide.Right, TAtlasAnchorSide.Bottom],
      TAtlasAnchorReason.WideBottom);
  end
  else if mLeft and mRight then
  begin
    Result := Suggestion([TAtlasAnchorSide.Left, TAtlasAnchorSide.Top, TAtlasAnchorSide.Right],
      TAtlasAnchorReason.Wide);
  end
  else if mRight and mBottom then
  begin
    Result := Suggestion([TAtlasAnchorSide.Right, TAtlasAnchorSide.Bottom], TAtlasAnchorReason.BottomRight);
  end
  else if mRight then
  begin
    Result := Suggestion([TAtlasAnchorSide.Top, TAtlasAnchorSide.Right], TAtlasAnchorReason.Right);
  end
  else if mBottom then
  begin
    Result := Suggestion([TAtlasAnchorSide.Left, TAtlasAnchorSide.Bottom], TAtlasAnchorReason.Bottom);
  end
  else
  begin
    Result := Suggestion(TAtlasAnchorSuggest.cDefault, TAtlasAnchorReason.Default);
  end;
end;

/// <summary>Bleibt der Vorschlag unangetastet von Reihe und Label (Align, vorhanden)?</summary>
function Fixed(const ASuggestion: TAtlasAnchorSuggestion): Boolean;
begin
  Result := ASuggestion.Reason in [TAtlasAnchorReason.Aligned, TAtlasAnchorReason.Existing];
end;

/// <summary>Kann AItem in einer Reihe stehen (nicht festgelegt, kein Label mit Feld)?</summary>
function RowMember(const AItems: TArray<TAtlasAnchorItem>; const AResult: TArray<TAtlasAnchorSuggestion>;
  AIndex: Integer): Boolean;
begin
  Result := not Fixed(AResult[AIndex]) and (AItems[AIndex].FocusOf = '');
end;

/// <summary>Gleiche Oberkante und waagerecht höchstens AGap auseinander?</summary>
function Adjacent(const A, B: TRect; AGap: Integer): Boolean;
begin
  Result := (Abs(A.Top - B.Top) <= TAtlasAnchorSuggest.cRowTolerance) and (B.Left - A.Right <= AGap) and
    (A.Left - B.Right <= AGap);
end;

/// <summary>Reihe um AIndex: Nachbarn mit gleicher Oberkante, verkettet mit Lücken bis AGap.</summary>
function RowOf(const AItems: TArray<TAtlasAnchorItem>; const AResult: TArray<TAtlasAnchorSuggestion>;
  AIndex, AGap: Integer): TArray<Boolean>;
var
  mGrown: Boolean;
  mIndex, mMember: Integer;
begin
  // Result kann das Feld des Aufrufers enthalten: erst leeren.
  Result := nil;
  SetLength(Result, Length(AItems));
  Result[AIndex] := True;
  repeat
    mGrown := False;
    for mIndex := 0 to High(AItems) do
    begin
      for mMember := 0 to High(AItems) do
      begin
        if not Result[mIndex] and Result[mMember] and RowMember(AItems, AResult, mIndex) and
          Adjacent(AItems[mMember].Bounds, AItems[mIndex].Bounds, AGap) then
        begin
          Result[mIndex] := True;
          mGrown := True;
        end;
      end;
    end;
  until not mGrown;
end;

/// <summary>Äußerste der Reihe ARow: die rechteste, wenn sie rechts verankert ist, sonst die linkeste.</summary>
function OuterOf(const AItems: TArray<TAtlasAnchorItem>; const ABase: TArray<TAtlasAnchorSuggestion>;
  const ARow: TArray<Boolean>; AIndex: Integer): Integer;
var
  mOther, mLeftmost, mRightmost: Integer;
begin
  mLeftmost := AIndex;
  mRightmost := AIndex;
  for mOther := 0 to High(AItems) do
  begin
    if ARow[mOther] and (AItems[mOther].Bounds.Left < AItems[mLeftmost].Bounds.Left) then
    begin
      mLeftmost := mOther;
    end;
    if ARow[mOther] and (AItems[mOther].Bounds.Right > AItems[mRightmost].Bounds.Right) then
    begin
      mRightmost := mOther;
    end;
  end;
  Result := mLeftmost;
  if TAtlasAnchorSide.Right in ABase[mRightmost].Anchors then
  begin
    Result := mRightmost;
  end;
end;

/// <summary>Reihen: alle Mitglieder bekommen die Anchors der äußersten.</summary>
procedure ApplyRows(const AItems: TArray<TAtlasAnchorItem>; AGap: Integer;
  var AResult: TArray<TAtlasAnchorSuggestion>);
var
  mBase: TArray<TAtlasAnchorSuggestion>;
  mIndex, mOuter: Integer;
begin
  mBase := Copy(AResult);
  for mIndex := 0 to High(AItems) do
  begin
    if not RowMember(AItems, mBase, mIndex) then
    begin
      Continue;
    end;
    mOuter := OuterOf(AItems, mBase, RowOf(AItems, mBase, mIndex, AGap), mIndex);
    if (mOuter <> mIndex) and (mBase[mIndex].Anchors <> mBase[mOuter].Anchors) then
    begin
      AResult[mIndex] := Suggestion(mBase[mOuter].Anchors, TAtlasAnchorReason.Row);
    end;
  end;
end;

function IndexOfName(const AItems: TArray<TAtlasAnchorItem>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Labels mit FocusControl: senkrecht wie das Feld, waagerecht links.</summary>
procedure ApplyLabels(const AItems: TArray<TAtlasAnchorItem>; var AResult: TArray<TAtlasAnchorSuggestion>);
var
  mIndex, mField: Integer;
  mAnchors: TAtlasAnchorSet;
begin
  for mIndex := 0 to High(AItems) do
  begin
    mField := IndexOfName(AItems, AItems[mIndex].FocusOf);
    if Fixed(AResult[mIndex]) or (AItems[mIndex].FocusOf = '') or (mField < 0) then
    begin
      Continue;
    end;
    mAnchors := [TAtlasAnchorSide.Left] + AResult[mField].Anchors * [TAtlasAnchorSide.Top, TAtlasAnchorSide.Bottom];
    if mAnchors = [TAtlasAnchorSide.Left] then
    begin
      Include(mAnchors, TAtlasAnchorSide.Top);
    end;
    AResult[mIndex] := Suggestion(mAnchors, TAtlasAnchorReason.FollowsField);
  end;
end;

class function TAtlasAnchorSuggest.Suggest(const AItems: TArray<TAtlasAnchorItem>; const AClient: TSize;
  AEdge: Integer; AKeepExisting: Boolean): TArray<TAtlasAnchorSuggestion>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Aligned then
    begin
      Result[mIndex] := Suggestion(AItems[mIndex].Existing, TAtlasAnchorReason.Aligned);
    end
    else if AKeepExisting and (AItems[mIndex].Existing <> cDefault) then
    begin
      Result[mIndex] := Suggestion(AItems[mIndex].Existing, TAtlasAnchorReason.Existing);
    end
    else
    begin
      Result[mIndex] := ByEdges(AItems[mIndex], AClient, AEdge);
    end;
  end;
  ApplyRows(AItems, AEdge, Result);
  ApplyLabels(AItems, Result);
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex].Changed := not Fixed(Result[mIndex]) and (Result[mIndex].Anchors <> AItems[mIndex].Existing);
  end;
end;

class function TAtlasAnchorSuggest.Text(AAnchors: TAtlasAnchorSet): string;
const
  cLetters: array [TAtlasAnchorSide] of Char = ('L', 'T', 'R', 'B');
var
  mSide: TAtlasAnchorSide;
begin
  Result := '';
  for mSide := Low(TAtlasAnchorSide) to High(TAtlasAnchorSide) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    if mSide in AAnchors then
    begin
      Result := Result + cLetters[mSide];
    end
    else
    begin
      Result := Result + '-';
    end;
  end;
end;

end.
