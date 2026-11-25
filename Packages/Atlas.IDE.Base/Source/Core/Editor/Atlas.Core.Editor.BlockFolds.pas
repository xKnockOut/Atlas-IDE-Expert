unit Atlas.Core.Editor.BlockFolds;

// Große Anweisungsblöcke einklappen (#2795, editor.blockFolds), ohne Open Tools API.
// Der Delphi-Editor faltet keine Anweisungsblöcke und die ToolsAPI kann keine
// Faltbereiche anmelden. Deshalb setzt Atlas eine Region in dieselben Zeilen:
//   if X then begin(*$REGION 'if X then'*)
//     …
//   end(*$ENDREGION*);
// Zeilennummern und Haltepunkte bleiben, die IDE faltet die Region. Die
// Klammerform (*$…*) schreibt kaum jemand von Hand; daran erkennt Atlas seine
// Marken und nimmt sie beim Aufklappen und vor dem Speichern wieder heraus.
// Die Blöcke liefert der Server (atlas/blockFolds): je Block die Stelle hinter
// dem öffnenden und dem schließenden Token. Zeilen 0-basiert wie im LSP.

interface

uses
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Plugin.Editor.Contract;

type
  /// <summary>Ein Block, wie der Server ihn meldet.</summary>
  TAtlasBlockFold = record
    /// <summary>if, else, for, while, with, case, on, try, repeat oder begin.</summary>
    Kind: string;
    /// <summary>Kopf des Blocks, Text der Region.</summary>
    Caption: string;
    /// <summary>Hinter dem öffnenden Token: hier beginnt die Region.</summary>
    OpenPos: TTextPosition;
    /// <summary>Hinter dem schließenden Token: hier endet die Region.</summary>
    ClosePos: TTextPosition;
    function LineCount: Integer;
    /// <summary>Liegt ALine (0-basiert) im Block, Kopf- und Schlusszeile eingeschlossen?</summary>
    function Contains(ALine: Integer): Boolean;
  end;

  /// <summary>Eine Marke von Atlas im Text.</summary>
  TAtlasBlockMarker = record
    /// <summary>Zeichenversatz (0-basiert) und Länge der Marke.</summary>
    Start: Integer;
    Count: Integer;
    /// <summary>Zeile (0-basiert).</summary>
    Line: Integer;
    /// <summary>(*$REGION …*) oder (*$ENDREGION*).</summary>
    Opening: Boolean;
  end;

  /// <summary>Ein gefalteter Block: passende Anfangs- und Schlussmarke.</summary>
  TAtlasFoldedBlock = record
    Open: TAtlasBlockMarker;
    Close: TAtlasBlockMarker;
    function Contains(ALine: Integer): Boolean;
  end;

  TAtlasBlockFolds = class
  public const
    cMethod = 'atlas/blockFolds';
    cOpenStart = '(*$REGION ''';
    cOpenEnd = '''*)';
    cClose = '(*$ENDREGION*)';
  public
    /// <summary>Parameter der Anfrage für die Datei AUri.</summary>
    class function Params(const AUri: string): string; static;
    /// <summary>Blöcke aus der Antwort {"blocks": [...]}; Unvollständiges wird übergangen.</summary>
    class function FromJson(const AValue: TJSONValue): TArray<TAtlasBlockFold>; static;
    /// <summary>Innerster Block um ALine (0-basiert) mit mindestens AMinLines Zeilen; -1 ohne.</summary>
    class function Innermost(const ABlocks: TArray<TAtlasBlockFold>; ALine, AMinLines: Integer): Integer; static;
    /// <summary>Blöcke ab AMinLines Zeilen, die in keinem anderen solchen liegen.</summary>
    class function Large(const ABlocks: TArray<TAtlasBlockFold>; AMinLines: Integer): TArray<TAtlasBlockFold>;
      static;
    /// <summary>Marken von Atlas in AText, nach Versatz.</summary>
    class function Markers(const AText: string): TArray<TAtlasBlockMarker>; static;
    /// <summary>Paare aus Anfangs- und Schlussmarke, außen vor innen; übrige Marken gehören zu keinem Paar.</summary>
    class function Folded(const AMarkers: TArray<TAtlasBlockMarker>): TArray<TAtlasFoldedBlock>; static;
    /// <summary>Innerstes Paar um ALine (0-basiert); -1 ohne.</summary>
    class function FoldedAt(const AFolded: TArray<TAtlasFoldedBlock>; ALine: Integer): Integer; static;
    /// <summary>Anfangsmarke mit ACaption.</summary>
    class function OpenMarker(const ACaption: string): string; static;
    /// <summary>Einfügungen für ABlocks in AText, aufsteigend; schon gefaltete Blöcke bleiben aus.</summary>
    class function FoldEdits(const AText: string; const ABlocks: TArray<TAtlasBlockFold>): TAtlasTextEdits; static;
    /// <summary>Löschungen der Marken AMarkers, aufsteigend.</summary>
    class function RemoveEdits(const AMarkers: TArray<TAtlasBlockMarker>): TAtlasTextEdits; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

{ TAtlasBlockFold }

function TAtlasBlockFold.LineCount: Integer;
begin
  Result := ClosePos.Line - OpenPos.Line + 1;
end;

function TAtlasBlockFold.Contains(ALine: Integer): Boolean;
begin
  Result := (ALine >= OpenPos.Line) and (ALine <= ClosePos.Line);
end;

{ TAtlasFoldedBlock }

function TAtlasFoldedBlock.Contains(ALine: Integer): Boolean;
begin
  Result := (ALine >= Open.Line) and (ALine <= Close.Line);
end;

{ TAtlasBlockFolds }

class function TAtlasBlockFolds.Params(const AUri: string): string;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
    Result := mParams.ToJSON([]);
  finally
    mParams.Free;
  end;
end;

function ReadPosition(const AItem: TJSONObject; const AName: string; out APosition: TTextPosition): Boolean;
var
  mLine, mCharacter: Integer;
begin
  Result := AItem.TryGetValue<Integer>(AName + '.line', mLine) and
    AItem.TryGetValue<Integer>(AName + '.character', mCharacter) and (mLine >= 0) and (mCharacter >= 0);
  APosition := TTextPosition.Create(mLine, mCharacter);
end;

class function TAtlasBlockFolds.FromJson(const AValue: TJSONValue): TArray<TAtlasBlockFold>;
var
  mBlocks: TJSONArray;
  mElement: TJSONValue;
  mItem: TJSONObject;
  mFold: TAtlasBlockFold;
  mList: TList<TAtlasBlockFold>;
begin
  Result := nil;
  if not ((AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<TJSONArray>('blocks', mBlocks)) then
  begin
    Exit;
  end;
  mList := TList<TAtlasBlockFold>.Create;
  try
    for mElement in mBlocks do
    begin
      if not (mElement is TJSONObject) then
      begin
        Continue;
      end;
      mItem := TJSONObject(mElement);
      mFold := Default(TAtlasBlockFold);
      mFold.Kind := mItem.GetValue<string>('kind', '');
      mFold.Caption := mItem.GetValue<string>('caption', '');
      if ReadPosition(mItem, 'open', mFold.OpenPos) and ReadPosition(mItem, 'close', mFold.ClosePos) and
        (TTextPosition.Compare(mFold.OpenPos, mFold.ClosePos) < 0) then
      begin
        mList.Add(mFold);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasBlockFolds.Innermost(const ABlocks: TArray<TAtlasBlockFold>; ALine, AMinLines: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ABlocks) do
  begin
    if ABlocks[mIndex].Contains(ALine) and (ABlocks[mIndex].LineCount >= AMinLines) and
      ((Result < 0) or (ABlocks[mIndex].LineCount < ABlocks[Result].LineCount)) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasBlockFolds.Large(const ABlocks: TArray<TAtlasBlockFold>;
  AMinLines: Integer): TArray<TAtlasBlockFold>;
var
  mList: TList<TAtlasBlockFold>;
  mFold: TAtlasBlockFold;
begin
  mList := TList<TAtlasBlockFold>.Create;
  try
    // Die Blöcke kommen nach öffnender Stelle; ein Block in einem schon gewählten bleibt aus.
    for mFold in ABlocks do
    begin
      if (mFold.LineCount >= AMinLines) and ((mList.Count = 0) or
        (TTextPosition.Compare(mFold.OpenPos, mList.Last.ClosePos) > 0)) then
      begin
        mList.Add(mFold);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Zeile des Versatzes AOffset; AFrom/ALine merken den letzten Stand, damit die Suche vorwärts läuft.
/// </summary>
function LineOf(const AText: string; AOffset: Integer; var AFrom, ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AFrom to AOffset - 1 do
  begin
    if AText.Chars[mIndex] = #10 then
    begin
      Inc(ALine);
    end;
  end;
  AFrom := AOffset;
  Result := ALine;
end;

class function TAtlasBlockFolds.Markers(const AText: string): TArray<TAtlasBlockMarker>;
var
  mList: TList<TAtlasBlockMarker>;
  mMarker: TAtlasBlockMarker;
  mOpen, mClose, mEnd, mFrom, mLine: Integer;
begin
  mList := TList<TAtlasBlockMarker>.Create;
  try
    mFrom := 0;
    mLine := 0;
    mOpen := AText.IndexOf(cOpenStart);
    mClose := AText.IndexOf(cClose);
    while (mOpen >= 0) or (mClose >= 0) do
    begin
      mMarker := Default(TAtlasBlockMarker);
      if (mOpen >= 0) and ((mClose < 0) or (mOpen < mClose)) then
      begin
        // Die Kopfzeile reicht nie über das Zeilenende.
        mEnd := AText.IndexOf(cOpenEnd, mOpen + Length(cOpenStart));
        if (mEnd >= 0) and (AText.IndexOf(#10, mOpen, mEnd - mOpen) < 0) then
        begin
          mMarker.Start := mOpen;
          mMarker.Count := mEnd + Length(cOpenEnd) - mOpen;
          mMarker.Opening := True;
          mMarker.Line := LineOf(AText, mOpen, mFrom, mLine);
          mList.Add(mMarker);
        end;
        mOpen := AText.IndexOf(cOpenStart, mOpen + Length(cOpenStart));
      end
      else
      begin
        mMarker.Start := mClose;
        mMarker.Count := Length(cClose);
        mMarker.Line := LineOf(AText, mClose, mFrom, mLine);
        mList.Add(mMarker);
        mClose := AText.IndexOf(cClose, mClose + Length(cClose));
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasBlockFolds.Folded(const AMarkers: TArray<TAtlasBlockMarker>): TArray<TAtlasFoldedBlock>;
var
  mOpen: TStack<TAtlasBlockMarker>;
  mList: TList<TAtlasFoldedBlock>;
  mMarker: TAtlasBlockMarker;
  mPair: TAtlasFoldedBlock;
begin
  mOpen := TStack<TAtlasBlockMarker>.Create;
  mList := TList<TAtlasFoldedBlock>.Create;
  try
    for mMarker in AMarkers do
    begin
      if mMarker.Opening then
      begin
        mOpen.Push(mMarker);
      end
      else if mOpen.Count > 0 then
      begin
        mPair.Open := mOpen.Pop;
        mPair.Close := mMarker;
        mList.Add(mPair);
      end;
    end;
    // Außen vor innen: nach Anfang, eindeutig, weil keine zwei Marken am selben Versatz stehen.
    mList.Sort(TComparer<TAtlasFoldedBlock>.Construct(
      function(const ALeft, ARight: TAtlasFoldedBlock): Integer
      begin
        Result := ALeft.Open.Start - ARight.Open.Start;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
    mOpen.Free;
  end;
end;

class function TAtlasBlockFolds.FoldedAt(const AFolded: TArray<TAtlasFoldedBlock>; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  // Außen vor innen sortiert: der letzte Treffer ist der innerste.
  Result := -1;
  for mIndex := 0 to High(AFolded) do
  begin
    if AFolded[mIndex].Contains(ALine) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasBlockFolds.OpenMarker(const ACaption: string): string;
begin
  Result := cOpenStart + ACaption.Replace('''', '"').Replace('*)', '* )') + cOpenEnd;
end;

class function TAtlasBlockFolds.FoldEdits(const AText: string;
  const ABlocks: TArray<TAtlasBlockFold>): TAtlasTextEdits;
var
  mLines: TLineTable;
  mList: TList<TAtlasTextEdit>;
  mFold: TAtlasBlockFold;
  mOpen, mClose: Integer;
begin
  mLines := TLineTable.Build(AText);
  mList := TList<TAtlasTextEdit>.Create;
  try
    for mFold in ABlocks do
    begin
      mOpen := mLines.OffsetAt(mFold.OpenPos);
      mClose := mLines.OffsetAt(mFold.ClosePos);
      if (mClose <= mOpen) or (Copy(AText, mOpen + 1, Length(cOpenStart)) = cOpenStart) then
      begin
        Continue;
      end;
      mList.Add(TAtlasTextEdit.Create(mOpen, 0, OpenMarker(mFold.Caption)));
      mList.Add(TAtlasTextEdit.Create(mClose, 0, cClose));
    end;
    // Aufsteigend; zwei Einfügungen an derselben Stelle gibt es nicht (hinter verschiedenen Token).
    mList.Sort(TComparer<TAtlasTextEdit>.Construct(
      function(const ALeft, ARight: TAtlasTextEdit): Integer
      begin
        Result := ALeft.Start - ARight.Start;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasBlockFolds.RemoveEdits(const AMarkers: TArray<TAtlasBlockMarker>): TAtlasTextEdits;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AMarkers));
  for mIndex := 0 to High(AMarkers) do
  begin
    Result[mIndex] := TAtlasTextEdit.Create(AMarkers[mIndex].Start, AMarkers[mIndex].Count, '');
  end;
end;

end.
