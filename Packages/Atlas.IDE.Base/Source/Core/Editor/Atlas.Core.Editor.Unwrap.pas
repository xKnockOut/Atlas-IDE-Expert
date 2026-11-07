unit Atlas.Core.Editor.Unwrap;

// Umschließung entfernen (#657), Kern im Plugin ohne VCL und ToolsAPI:
// Argumente für atlas.server.unwrap, die Antwort als Einträge der Liste (je
// Konstrukt und Variante einer, das innerste Konstrukt zuerst), die Stücke
// einer Zeile für die Vorschau (bleibt grün, entfällt rot) und das
// WorkspaceEdit des gewählten Eintrags. Ein Konstrukt ohne Variante (with
// nicht auflösbar) bleibt als Eintrag mit Hinweis stehen, lässt sich aber
// nicht übernehmen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TAtlasUnwrapEntry = record
    /// <summary>Konstrukt: beginEnd, tryFinally, tryExcept, ifThen, withDo, forDo, whileDo, repeatUntil, ifdef,
    /// region.</summary>
    Kind: string;
    /// <summary>Variante: body, keepFinally, dropFinally, then, else, branch; '' ohne Variante.</summary>
    VariantKind: string;
    /// <summary>Nummer des Zweigs ab 0 bei Direktiven.</summary>
    Branch: Integer;
    /// <summary>Zahl der Varianten des Konstrukts.</summary>
    VariantCount: Integer;
    /// <summary>Hinweis: multipleRaise, loopVariable, withUnresolved oder ''.</summary>
    Note: string;
    NoteText: string;
    /// <summary>Erste Zeile des Konstrukts ab 0.</summary>
    Line: Integer;
    Edits: TArray<TLspTextEdit>;
    Keep: TArray<TLspRange>;
    Remove: TArray<TLspRange>;
    /// <summary>Lässt sich übernehmen (hat Edits)?</summary>
    function Available: Boolean;
  end;

  /// <summary>Stück einer Zeile in der Vorschau, Zeichen ab 0, Ende ausschließlich.</summary>
  TAtlasUnwrapSpan = record
    Start: Integer;
    Stop: Integer;
    Keep: Boolean;
  end;

  TAtlasUnwrap = class
  public const
    Command = 'atlas.server.unwrap';
    /// <summary>Strg+Umschalt+Entf.</summary>
    DefaultKey = $602E;
  public
    /// <summary>[uri, position, Einrückungsbreite]; AIndentWidth &lt;= 0 = Formatierstil des Servers.</summary>
    class function Arguments(const AUri: string; ALine, ACharacter, AIndentWidth: Integer): string; static;
    /// <summary>Einträge aus der Antwort; nil bei leerer oder fremder Antwort.</summary>
    class function ReadEntries(const AAnswer: TJSONValue): TArray<TAtlasUnwrapEntry>; static;
    /// <summary>Genau ein Konstrukt mit einer Variante: Die Liste entfällt, die Vorschau erscheint direkt.</summary>
    class function SingleEntry(const AEntries: TArray<TAtlasUnwrapEntry>): Boolean; static;
    /// <summary>Erster übernehmbarer Eintrag ab AFrom in Richtung ADelta (ringsum); -1 ohne.</summary>
    class function NextAvailable(const AEntries: TArray<TAtlasUnwrapEntry>; AFrom, ADelta: Integer): Integer; static;
    /// <summary>Stücke der Vorschau in Zeile ALine (ab 0), nach Anfang sortiert.</summary>
    class function SpansOnLine(const AEntry: TAtlasUnwrapEntry; ALine: Integer): TArray<TAtlasUnwrapSpan>; static;
    /// <summary>Erste und letzte Zeile der Vorschau; False ohne Bereiche.</summary>
    class function LineSpan(const AEntry: TAtlasUnwrapEntry; out AFirst, ALast: Integer): Boolean; static;
    /// <summary>Die Edits des Eintrags als Änderung an AFileName.</summary>
    class function EditOf(const AEntry: TAtlasUnwrapEntry; const AFileName: string): TLspWorkspaceEdit; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

function ReadPosition(const AValue: TJSONValue; out APosition: TLspTextPosition): Boolean;
var
  mLine, mCharacter: Integer;
begin
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>('line', mLine) and
    TJSONObject(AValue).TryGetValue<Integer>('character', mCharacter);
  if Result then
  begin
    APosition := TLspTextPosition.Create(mLine, mCharacter);
  end;
end;

function ReadRange(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and ReadPosition(TJSONObject(AValue).GetValue('start'), ARange.StartPos) and
    ReadPosition(TJSONObject(AValue).GetValue('end'), ARange.EndPos);
end;

function ReadRanges(const AValue: TJSONValue): TArray<TLspRange>;
var
  mItem: TJSONValue;
  mRange: TLspRange;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if ReadRange(mItem, mRange) then
      begin
        Result := Result + [mRange];
      end;
    end;
  end;
end;

function ReadEdits(const AValue: TJSONValue): TArray<TLspTextEdit>;
var
  mItem: TJSONValue;
  mEdit: TLspTextEdit;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if TLspTextEdit.FromJson(mItem, mEdit) then
      begin
        Result := Result + [mEdit];
      end;
    end;
  end;
end;

function StringOf(const AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
  begin
    Result := AObject.GetValue(AName).Value;
  end;
end;

{ TAtlasUnwrapEntry }

function TAtlasUnwrapEntry.Available: Boolean;
begin
  Result := Length(Edits) > 0;
end;

{ TAtlasUnwrap }

class function TAtlasUnwrap.Arguments(const AUri: string; ALine, ACharacter, AIndentWidth: Integer): string;
var
  mList: TJSONArray;
  mPosition: TJSONObject;
begin
  mList := TJSONArray.Create;
  try
    mList.Add(AUri);
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ALine));
    mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
    mList.AddElement(mPosition);
    mList.Add(AIndentWidth);
    Result := mList.ToJSON;
  finally
    mList.Free;
  end;
end;

/// <summary>Eintrag ohne Variante: Art, Hinweis und Zeile des Kandidaten.</summary>
function CandidateEntry(const ACandidate: TJSONObject): TAtlasUnwrapEntry;
var
  mRange: TLspRange;
begin
  Result := Default(TAtlasUnwrapEntry);
  Result.Kind := StringOf(ACandidate, 'kind');
  Result.Note := StringOf(ACandidate, 'note');
  Result.NoteText := StringOf(ACandidate, 'noteText');
  if ReadRange(ACandidate.GetValue('range'), mRange) then
  begin
    Result.Line := mRange.StartPos.Line;
  end;
end;

/// <summary>AEntry mit der Variante AChoice {kind, branch, edits, keep, remove}.</summary>
function VariantEntry(const AEntry: TAtlasUnwrapEntry; const AChoice: TJSONObject): TAtlasUnwrapEntry;
var
  mBranch: Integer;
begin
  Result := AEntry;
  Result.VariantKind := StringOf(AChoice, 'kind');
  Result.Branch := 0;
  if AChoice.TryGetValue<Integer>('branch', mBranch) then
  begin
    Result.Branch := mBranch;
  end;
  Result.Edits := ReadEdits(AChoice.GetValue('edits'));
  Result.Keep := ReadRanges(AChoice.GetValue('keep'));
  Result.Remove := ReadRanges(AChoice.GetValue('remove'));
end;

/// <summary>Einträge eines Kandidaten: je Variante einer, ohne Varianten einer mit Hinweis.</summary>
function CandidateEntries(const ACandidate: TJSONObject): TArray<TAtlasUnwrapEntry>;
var
  mEntry: TAtlasUnwrapEntry;
  mVariants: TJSONArray;
  mVariantItem: TJSONValue;
begin
  mEntry := CandidateEntry(ACandidate);
  mVariants := nil;
  if ACandidate.GetValue('variants') is TJSONArray then
  begin
    mVariants := TJSONArray(ACandidate.GetValue('variants'));
  end;
  if (mVariants = nil) or (mVariants.Count = 0) then
  begin
    // Nicht übernehmbar, aber mit Hinweis in der Liste.
    Result := TArray<TAtlasUnwrapEntry>.Create(mEntry);
  end
  else
  begin
    Result := nil;
    mEntry.VariantCount := mVariants.Count;
    for mVariantItem in mVariants do
    begin
      if mVariantItem is TJSONObject then
      begin
        Result := Result + [VariantEntry(mEntry, TJSONObject(mVariantItem))];
      end;
    end;
  end;
end;

class function TAtlasUnwrap.ReadEntries(const AAnswer: TJSONValue): TArray<TAtlasUnwrapEntry>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if (AAnswer is TJSONObject) and (TJSONObject(AAnswer).GetValue('candidates') is TJSONArray) then
  begin
    for mItem in TJSONArray(TJSONObject(AAnswer).GetValue('candidates')) do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + CandidateEntries(TJSONObject(mItem));
      end;
    end;
  end;
end;

class function TAtlasUnwrap.SingleEntry(const AEntries: TArray<TAtlasUnwrapEntry>): Boolean;
begin
  Result := (Length(AEntries) = 1) and AEntries[0].Available;
end;

class function TAtlasUnwrap.NextAvailable(const AEntries: TArray<TAtlasUnwrapEntry>; AFrom, ADelta: Integer): Integer;
var
  mCount, mStep, mIndex: Integer;
begin
  Result := -1;
  mCount := Length(AEntries);
  if mCount = 0 then
  begin
    Exit;
  end;
  if ADelta = 0 then
  begin
    ADelta := 1;
  end;
  for mStep := 0 to mCount - 1 do
  begin
    mIndex := ((AFrom + mStep * ADelta) mod mCount + mCount) mod mCount;
    if AEntries[mIndex].Available then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasUnwrap.SpansOnLine(const AEntry: TAtlasUnwrapEntry; ALine: Integer): TArray<TAtlasUnwrapSpan>;

  procedure AddFrom(const ARanges: TArray<TLspRange>; AKeep: Boolean; var ASpans: TArray<TAtlasUnwrapSpan>);
  var
    mRange: TLspRange;
    mSpan: TAtlasUnwrapSpan;
  begin
    for mRange in ARanges do
    begin
      if (mRange.StartPos.Line > ALine) or (mRange.EndPos.Line < ALine) then
      begin
        Continue;
      end;
      mSpan.Start := 0;
      if mRange.StartPos.Line = ALine then
      begin
        mSpan.Start := mRange.StartPos.Character;
      end;
      mSpan.Stop := MaxInt;
      if mRange.EndPos.Line = ALine then
      begin
        mSpan.Stop := mRange.EndPos.Character;
      end;
      mSpan.Keep := AKeep;
      if mSpan.Stop > mSpan.Start then
      begin
        ASpans := ASpans + [mSpan];
      end;
    end;
  end;

begin
  Result := nil;
  AddFrom(AEntry.Keep, True, Result);
  AddFrom(AEntry.Remove, False, Result);
  TArray.Sort<TAtlasUnwrapSpan>(Result, TComparer<TAtlasUnwrapSpan>.Construct(
    function(const A, B: TAtlasUnwrapSpan): Integer
    begin
      Result := A.Start - B.Start;
    end));
end;

class function TAtlasUnwrap.LineSpan(const AEntry: TAtlasUnwrapEntry; out AFirst, ALast: Integer): Boolean;
var
  mRange: TLspRange;
begin
  AFirst := MaxInt;
  ALast := -1;
  for mRange in AEntry.Keep + AEntry.Remove do
  begin
    if mRange.StartPos.Line < AFirst then
    begin
      AFirst := mRange.StartPos.Line;
    end;
    if mRange.EndPos.Line > ALast then
    begin
      ALast := mRange.EndPos.Line;
    end;
  end;
  Result := ALast >= 0;
  if not Result then
  begin
    AFirst := -1;
  end;
end;

class function TAtlasUnwrap.EditOf(const AEntry: TAtlasUnwrapEntry; const AFileName: string): TLspWorkspaceEdit;
var
  mFileEdits: TLspFileEdits;
begin
  Result := TLspWorkspaceEdit.FromJson(nil);
  if not AEntry.Available then
  begin
    Exit;
  end;
  mFileEdits.FileName := AFileName;
  mFileEdits.Edits := AEntry.Edits;
  Result.Files := [mFileEdits];
end;

end.
