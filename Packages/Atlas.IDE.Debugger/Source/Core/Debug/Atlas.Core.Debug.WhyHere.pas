unit Atlas.Core.Debug.WhyHere;

// „Warum bin ich hier?“ (#1878), ohne VCL und Open Tools API:
//   - Antwort des Servers (atlas.server.enclosingConditions) lesen: die
//     umgebenden Steueranweisungen mit dem Baum ihrer Bedingung.
//   - Reihenfolge der Auswertung: Block für Block, im Baum von links nach
//     rechts. Ausgewertet werden Werte (value) und Vergleiche (compare), die
//     keinen Aufruf enthalten; Vergleiche als Ganzes (Wahrheitswert) und ihre
//     beiden Seiten (für die Anzeige). and, or, xor und not rechnet Atlas
//     selbst aus.
//   - Kurzschluss: Bei A and B mit A = False (bzw. A or B mit A = True) ist B
//     „nicht nötig“ und wird nicht ausgewertet.
//   - Aufrufe (auch Getter) bleiben „nicht ausgewertet“, bis der Benutzer sie
//     freigibt (Allow); dann wertet das Plugin sie mit Nebenwirkungen aus.
//   - Text je Kopfzeile: „True and (1200 > 1000) → True“, „I = 3 von 7“,
//     „Art = paRabatt → paRabatt“. Die Wörter liefert die Oberfläche
//     (TAtlasWhyHereTexts), damit dieser Teil ohne Texttabellen auskommt.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasWhyHereState = (Pending, Value, Failed, Skipped);
  TAtlasWhyHereTruth = (Unknown, IsFalse, IsTrue);
  {$SCOPEDENUMS OFF}

  TAtlasWhyHerePart = record
    /// <summary>and, or, xor, not, compare oder value.</summary>
    Kind: string;
    Operator_: string;
    Text: string;
    Parent: Integer;
    /// <summary>Enthält einen Aufruf; wird erst nach Allow ausgewertet.</summary>
    Call: Boolean;
    /// <summary>Aufruf vom Benutzer freigegeben.</summary>
    Allowed: Boolean;
    State: TAtlasWhyHereState;
    Value: string;
  end;

  TAtlasWhyHereBlock = record
    /// <summary>if, while, repeat, for, forIn, case oder with.</summary>
    Kind: string;
    /// <summary>Zeile (ab 0), an deren Ende der Text steht.</summary>
    Line: Integer;
    Branch: string;
    Descending: Boolean;
    Parts: TArray<TAtlasWhyHerePart>;
  end;

  TAtlasWhyHereBlocks = TArray<TAtlasWhyHereBlock>;

  /// <summary>Wörter der Anzeige, von der Oberfläche in der Sprache der IDE.</summary>
  TAtlasWhyHereTexts = record
    /// <summary>Kurzschluss: Teil nicht ausgewertet, weil schon entschieden („nicht nötig“).</summary>
    NotNeeded: string;
    /// <summary>Aufruf, noch nicht ausgewertet („‹Aufruf›“).</summary>
    NotEvaluated: string;
    /// <summary>Auswertung gescheitert („?“).</summary>
    Failed: string;
    /// <summary>else-Zweig eines if bzw. case („else-Zweig“).</summary>
    ElseBranch: string;
    /// <summary>for: „von“ in „I = 3 von 7“.</summary>
    Of_: string;
  end;

  /// <summary>Ein Teil, den das Plugin auswerten soll.</summary>
  TAtlasWhyHereRef = record
    Block: Integer;
    Part: Integer;
    Expression: string;
    /// <summary>Freigegebener Aufruf: mit Nebenwirkungen auswerten.</summary>
    SideEffects: Boolean;
  end;

  TAtlasWhyHere = class
  public const
    cCommand = 'atlas.server.enclosingConditions';
    /// <summary>Längere Werte werden gekürzt.</summary>
    cMaxValueLength = 40;
  private
    FFileName: string;
    FBlocks: TAtlasWhyHereBlocks;
    function ChildrenOf(ABlock, APart: Integer): TArray<Integer>;
    function Evaluable(ABlock, APart: Integer): Boolean;
    function Render(ABlock, APart: Integer; const ATexts: TAtlasWhyHereTexts): string;
    function RenderValue(ABlock, APart: Integer; const ATexts: TAtlasWhyHereTexts): string;
    function TruthText(ATruth: TAtlasWhyHereTruth; const ATexts: TAtlasWhyHereTexts): string;
    function LogicalTruth(ABlock, APart: Integer): TAtlasWhyHereTruth;
    function BlockText(ABlock: Integer; const ATexts: TAtlasWhyHereTexts): string;
    class function ReadBlock(AItem: TJSONObject): TAtlasWhyHereBlock; static;
    class function ReadPart(AItem: TJSONObject): TAtlasWhyHerePart; static;
  public
    /// <summary>Argumente des Befehls als JSON: [uri, line, depth].</summary>
    class function Arguments(const AUri: string; ALine, ADepth: Integer): string; static;
    /// <summary>Antwort des Servers lesen; False ohne format 1.</summary>
    class function ReadAnswer(AJson: TJSONValue; out ABlocks: TAtlasWhyHereBlocks): Boolean; static;
    /// <summary>Neuer Halt in AFileName mit ABlocks; Teile, die nichts auswerten, sind sofort fertig.</summary>
    procedure Start(const AFileName: string; const ABlocks: TAtlasWhyHereBlocks);
    procedure Clear;
    function Active: Boolean;
    /// <summary>Nächster Teil, den das Plugin auswerten soll; False, wenn nichts mehr aussteht.</summary>
    function NextPending(out ARef: TAtlasWhyHereRef): Boolean;
    /// <summary>Wert eines Teils; AOk = False: Auswertung gescheitert.</summary>
    procedure Put(const ARef: TAtlasWhyHereRef; const AValue: string; AOk: Boolean);
    /// <summary>Alle Aufrufe der Blöcke an ALine freigeben; Ergebnis: ihre Texte (für die Rückfrage), leer ohne.
    /// </summary>
    function CallsAt(ALine: Integer): TArray<string>;
    /// <summary>Gibt die Aufrufe aus CallsAt(ALine) frei; NextPending liefert sie danach mit SideEffects.</summary>
    procedure AllowCalls(ALine: Integer);
    /// <summary>Wird der Teil gebraucht? False, wenn ein Kurzschluss vorher entschieden hat.</summary>
    function Needed(ABlock, APart: Integer): Boolean;
    function Truth(ABlock, APart: Integer): TAtlasWhyHereTruth;
    /// <summary>Text am Ende der Zeile ALine (ab 0) in AFileName; '' ohne Block dort.</summary>
    function LineText(const AFileName: string; ALine: Integer; const ATexts: TAtlasWhyHereTexts): string;
    property FileName: string read FFileName;
    property Blocks: TAtlasWhyHereBlocks read FBlocks;
  end;

implementation

const
  cArrow = ' → ';

{ TAtlasWhyHere }

class function TAtlasWhyHere.Arguments(const AUri: string; ALine, ADepth: Integer): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(ALine);
    mItems.Add(ADepth);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

function IntOf(AItem: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := AItem.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end;
end;

function TextOf(AItem: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AItem.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function FlagOf(AItem: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AItem.GetValue(AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

class function TAtlasWhyHere.ReadPart(AItem: TJSONObject): TAtlasWhyHerePart;
begin
  Result := Default(TAtlasWhyHerePart);
  Result.Kind := TextOf(AItem, 'kind');
  Result.Operator_ := TextOf(AItem, 'operator');
  Result.Text := TextOf(AItem, 'text');
  Result.Parent := IntOf(AItem, 'parent', -1);
  Result.Call := FlagOf(AItem, 'call');
end;

class function TAtlasWhyHere.ReadBlock(AItem: TJSONObject): TAtlasWhyHereBlock;
var
  mParts: TJSONValue;
  mIndex: Integer;
begin
  Result := Default(TAtlasWhyHereBlock);
  Result.Kind := TextOf(AItem, 'kind');
  Result.Line := IntOf(AItem, 'line', -1);
  Result.Branch := TextOf(AItem, 'branch');
  Result.Descending := FlagOf(AItem, 'descending');
  mParts := AItem.GetValue('parts');
  if not (mParts is TJSONArray) then
  begin
    Exit;
  end;
  SetLength(Result.Parts, TJSONArray(mParts).Count);
  for mIndex := 0 to TJSONArray(mParts).Count - 1 do
  begin
    if TJSONArray(mParts).Items[mIndex] is TJSONObject then
    begin
      Result.Parts[mIndex] := ReadPart(TJSONObject(TJSONArray(mParts).Items[mIndex]));
    end;
  end;
end;

class function TAtlasWhyHere.ReadAnswer(AJson: TJSONValue; out ABlocks: TAtlasWhyHereBlocks): Boolean;
var
  mBlocks: TJSONValue;
  mItem: TJSONValue;
  mBlock: TAtlasWhyHereBlock;
begin
  ABlocks := nil;
  Result := (AJson is TJSONObject) and (IntOf(TJSONObject(AJson), 'format', 0) = 1);
  if not Result then
  begin
    Exit;
  end;
  mBlocks := TJSONObject(AJson).GetValue('blocks');
  if not (mBlocks is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mBlocks) do
  begin
    if mItem is TJSONObject then
    begin
      mBlock := ReadBlock(TJSONObject(mItem));
      if (mBlock.Kind <> '') and (mBlock.Line >= 0) then
      begin
        ABlocks := ABlocks + [mBlock];
      end;
    end;
  end;
end;

procedure TAtlasWhyHere.Start(const AFileName: string; const ABlocks: TAtlasWhyHereBlocks);
var
  mBlock, mPart: Integer;
begin
  FFileName := AFileName;
  FBlocks := Copy(ABlocks);
  for mBlock := 0 to High(FBlocks) do
  begin
    for mPart := 0 to High(FBlocks[mBlock].Parts) do
    begin
      FBlocks[mBlock].Parts[mPart].State := TAtlasWhyHereState.Pending;
      FBlocks[mBlock].Parts[mPart].Value := '';
      // with ist nur ein Hinweis; bei for … in zählt nur die Schleifenvariable, nicht die Sammlung.
      // and, or, xor und not rechnet Atlas selbst aus.
      if (FBlocks[mBlock].Kind = 'with') or ((FBlocks[mBlock].Kind = 'forIn') and (mPart > 0)) or
        not Evaluable(mBlock, mPart) then
      begin
        FBlocks[mBlock].Parts[mPart].State := TAtlasWhyHereState.Skipped;
      end;
    end;
  end;
end;

procedure TAtlasWhyHere.Clear;
begin
  FFileName := '';
  FBlocks := nil;
end;

function TAtlasWhyHere.Active: Boolean;
begin
  Result := Length(FBlocks) > 0;
end;

function TAtlasWhyHere.ChildrenOf(ABlock, APart: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := APart + 1 to High(FBlocks[ABlock].Parts) do
  begin
    if FBlocks[ABlock].Parts[mIndex].Parent = APart then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function TAtlasWhyHere.Evaluable(ABlock, APart: Integer): Boolean;
var
  mKind: string;
begin
  // Nur Werte und Vergleiche; die logischen Verknüpfungen rechnet Atlas selbst.
  mKind := FBlocks[ABlock].Parts[APart].Kind;
  Result := (mKind = 'value') or (mKind = 'compare');
end;

function TAtlasWhyHere.Needed(ABlock, APart: Integer): Boolean;
var
  mChild, mParent, mSibling: Integer;
  mTruth: TAtlasWhyHereTruth;
  mKind: string;
begin
  Result := True;
  mChild := APart;
  mParent := FBlocks[ABlock].Parts[APart].Parent;
  while Result and (mParent >= 0) do
  begin
    mKind := FBlocks[ABlock].Parts[mParent].Kind;
    if (mKind = 'and') or (mKind = 'or') then
    begin
      for mSibling in ChildrenOf(ABlock, mParent) do
      begin
        if mSibling >= mChild then
        begin
          Break;
        end;
        mTruth := Truth(ABlock, mSibling);
        if ((mKind = 'and') and (mTruth = TAtlasWhyHereTruth.IsFalse)) or
          ((mKind = 'or') and (mTruth = TAtlasWhyHereTruth.IsTrue)) then
        begin
          Exit(False);
        end;
      end;
    end;
    mChild := mParent;
    mParent := FBlocks[ABlock].Parts[mParent].Parent;
  end;
end;

function TAtlasWhyHere.NextPending(out ARef: TAtlasWhyHereRef): Boolean;
var
  mBlock, mPart: Integer;
  mItem: TAtlasWhyHerePart;
begin
  ARef := Default(TAtlasWhyHereRef);
  for mBlock := 0 to High(FBlocks) do
  begin
    for mPart := 0 to High(FBlocks[mBlock].Parts) do
    begin
      mItem := FBlocks[mBlock].Parts[mPart];
      if (mItem.State <> TAtlasWhyHereState.Pending) or (mItem.Call and not mItem.Allowed) then
      begin
        Continue;
      end;
      if not Needed(mBlock, mPart) then
      begin
        Continue;
      end;
      ARef.Block := mBlock;
      ARef.Part := mPart;
      ARef.Expression := mItem.Text;
      ARef.SideEffects := mItem.Call;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasWhyHere.Put(const ARef: TAtlasWhyHereRef; const AValue: string; AOk: Boolean);
begin
  if (ARef.Block < 0) or (ARef.Block > High(FBlocks)) or (ARef.Part < 0) or
    (ARef.Part > High(FBlocks[ARef.Block].Parts)) then
  begin
    Exit;
  end;
  if AOk then
  begin
    FBlocks[ARef.Block].Parts[ARef.Part].State := TAtlasWhyHereState.Value;
    FBlocks[ARef.Block].Parts[ARef.Part].Value := AValue;
  end
  else
  begin
    FBlocks[ARef.Block].Parts[ARef.Part].State := TAtlasWhyHereState.Failed;
    FBlocks[ARef.Block].Parts[ARef.Part].Value := '';
  end;
end;

function TAtlasWhyHere.CallsAt(ALine: Integer): TArray<string>;
var
  mBlock, mPart: Integer;
  mItem: TAtlasWhyHerePart;
begin
  Result := nil;
  for mBlock := 0 to High(FBlocks) do
  begin
    if FBlocks[mBlock].Line <> ALine then
    begin
      Continue;
    end;
    for mPart := 0 to High(FBlocks[mBlock].Parts) do
    begin
      mItem := FBlocks[mBlock].Parts[mPart];
      // Nur die innersten Aufrufe nennen: ein Vergleich mit Aufruf nennt seine Seite.
      if mItem.Call and not mItem.Allowed and Evaluable(mBlock, mPart) and
        (mItem.State = TAtlasWhyHereState.Pending) and (Length(ChildrenOf(mBlock, mPart)) = 0) then
      begin
        Result := Result + [mItem.Text];
      end;
    end;
  end;
end;

procedure TAtlasWhyHere.AllowCalls(ALine: Integer);
var
  mBlock, mPart: Integer;
begin
  for mBlock := 0 to High(FBlocks) do
  begin
    if FBlocks[mBlock].Line = ALine then
    begin
      for mPart := 0 to High(FBlocks[mBlock].Parts) do
      begin
        if FBlocks[mBlock].Parts[mPart].Call then
        begin
          FBlocks[mBlock].Parts[mPart].Allowed := True;
        end;
      end;
    end;
  end;
end;

function TruthOfText(const AValue: string): TAtlasWhyHereTruth;
begin
  Result := TAtlasWhyHereTruth.Unknown;
  if SameText(Trim(AValue), 'True') then
  begin
    Result := TAtlasWhyHereTruth.IsTrue;
  end
  else if SameText(Trim(AValue), 'False') then
  begin
    Result := TAtlasWhyHereTruth.IsFalse;
  end;
end;

function TAtlasWhyHere.LogicalTruth(ABlock, APart: Integer): TAtlasWhyHereTruth;
var
  mKind: string;
  mChild: Integer;
  mTruth: TAtlasWhyHereTruth;
  mDecides, mKeeps: TAtlasWhyHereTruth;
  mAllKnown, mParity: Boolean;
begin
  mKind := FBlocks[ABlock].Parts[APart].Kind;
  // and: ein False entscheidet; or: ein True. xor: alle müssen bekannt sein.
  mDecides := TAtlasWhyHereTruth.IsTrue;
  mKeeps := TAtlasWhyHereTruth.IsFalse;
  if mKind = 'and' then
  begin
    mDecides := TAtlasWhyHereTruth.IsFalse;
    mKeeps := TAtlasWhyHereTruth.IsTrue;
  end;
  mAllKnown := True;
  mParity := False;
  for mChild in ChildrenOf(ABlock, APart) do
  begin
    mTruth := Truth(ABlock, mChild);
    if (mKind <> 'xor') and (mTruth = mDecides) then
    begin
      Exit(mDecides);
    end;
    if mTruth = TAtlasWhyHereTruth.Unknown then
    begin
      mAllKnown := False;
    end;
    mParity := mParity xor (mTruth = TAtlasWhyHereTruth.IsTrue);
  end;
  Result := TAtlasWhyHereTruth.Unknown;
  if not mAllKnown then
  begin
    Exit;
  end;
  Result := mKeeps;
  if mKind = 'xor' then
  begin
    Result := TAtlasWhyHereTruth.IsFalse;
    if mParity then
    begin
      Result := TAtlasWhyHereTruth.IsTrue;
    end;
  end;
end;

function TAtlasWhyHere.Truth(ABlock, APart: Integer): TAtlasWhyHereTruth;
var
  mItem: TAtlasWhyHerePart;
  mChildren: TArray<Integer>;
begin
  mItem := FBlocks[ABlock].Parts[APart];
  if (mItem.Kind = 'and') or (mItem.Kind = 'or') or (mItem.Kind = 'xor') then
  begin
    Exit(LogicalTruth(ABlock, APart));
  end;
  if mItem.Kind = 'not' then
  begin
    Result := TAtlasWhyHereTruth.Unknown;
    mChildren := ChildrenOf(ABlock, APart);
    if Length(mChildren) = 1 then
    begin
      case Truth(ABlock, mChildren[0]) of
        TAtlasWhyHereTruth.IsTrue:
          Result := TAtlasWhyHereTruth.IsFalse;
        TAtlasWhyHereTruth.IsFalse:
          Result := TAtlasWhyHereTruth.IsTrue;
      end;
    end;
    Exit;
  end;
  Result := TAtlasWhyHereTruth.Unknown;
  if mItem.State = TAtlasWhyHereState.Value then
  begin
    Result := TruthOfText(mItem.Value);
  end;
end;

function TAtlasWhyHere.TruthText(ATruth: TAtlasWhyHereTruth; const ATexts: TAtlasWhyHereTexts): string;
begin
  case ATruth of
    TAtlasWhyHereTruth.IsTrue:
      Result := 'True';
    TAtlasWhyHereTruth.IsFalse:
      Result := 'False';
  else
    Result := ATexts.Failed;
  end;
end;

function Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(AText);
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

function TAtlasWhyHere.RenderValue(ABlock, APart: Integer; const ATexts: TAtlasWhyHereTexts): string;
var
  mItem: TAtlasWhyHerePart;
begin
  mItem := FBlocks[ABlock].Parts[APart];
  case mItem.State of
    TAtlasWhyHereState.Value:
      Result := Shorten(mItem.Value, cMaxValueLength);
    TAtlasWhyHereState.Failed:
      Result := ATexts.Failed;
    TAtlasWhyHereState.Skipped:
      Result := mItem.Text;
  else
    Result := '…';
    if mItem.Call and not mItem.Allowed then
    begin
      Result := ATexts.NotEvaluated;
    end;
  end;
end;

function TAtlasWhyHere.Render(ABlock, APart: Integer; const ATexts: TAtlasWhyHereTexts): string;
var
  mItem: TAtlasWhyHerePart;
  mChildren: TArray<Integer>;
  mTexts: TArray<string>;
  mChild: Integer;
begin
  mItem := FBlocks[ABlock].Parts[APart];
  if not Needed(ABlock, APart) then
  begin
    Exit(ATexts.NotNeeded);
  end;
  mChildren := ChildrenOf(ABlock, APart);
  if mItem.Kind = 'value' then
  begin
    Exit(RenderValue(ABlock, APart, ATexts));
  end;
  if (mItem.Kind = 'compare') and (Length(mChildren) = 2) then
  begin
    Exit('(' + Render(ABlock, mChildren[0], ATexts) + ' ' + mItem.Operator_ + ' ' +
      Render(ABlock, mChildren[1], ATexts) + ')');
  end;
  if (mItem.Kind = 'not') and (Length(mChildren) = 1) then
  begin
    Exit('not ' + Render(ABlock, mChildren[0], ATexts));
  end;
  mTexts := nil;
  for mChild in mChildren do
  begin
    mTexts := mTexts + [Render(ABlock, mChild, ATexts)];
  end;
  Result := string.Join(' ' + mItem.Operator_ + ' ', mTexts);
  if Result = '' then
  begin
    Result := RenderValue(ABlock, APart, ATexts);
  end;
end;

function TAtlasWhyHere.BlockText(ABlock: Integer; const ATexts: TAtlasWhyHereTexts): string;
var
  mBlock: TAtlasWhyHereBlock;
  mParts: TArray<string>;
  mIndex: Integer;
begin
  mBlock := FBlocks[ABlock];
  Result := '';
  if Length(mBlock.Parts) = 0 then
  begin
    Exit;
  end;
  if mBlock.Kind = 'with' then
  begin
    mParts := nil;
    for mIndex := 0 to High(mBlock.Parts) do
    begin
      mParts := mParts + [mBlock.Parts[mIndex].Text];
    end;
    Exit('with ' + string.Join(', ', mParts));
  end;
  if (mBlock.Kind = 'for') and (Length(mBlock.Parts) = 2) then
  begin
    Exit(mBlock.Parts[0].Text + ' = ' + Render(ABlock, 0, ATexts) + ' ' + ATexts.Of_ + ' ' + Render(ABlock, 1, ATexts));
  end;
  if mBlock.Kind = 'forIn' then
  begin
    Exit(mBlock.Parts[0].Text + ' = ' + Render(ABlock, 0, ATexts));
  end;
  if mBlock.Kind = 'case' then
  begin
    Result := mBlock.Parts[0].Text + ' = ' + Render(ABlock, 0, ATexts) + cArrow;
    if mBlock.Branch = 'else' then
    begin
      Exit(Result + ATexts.ElseBranch);
    end;
    Exit(Result + mBlock.Branch);
  end;
  // if, while, repeat: Bedingung mit Werten und Ergebnis.
  Result := Render(ABlock, 0, ATexts) + cArrow + TruthText(Truth(ABlock, 0), ATexts);
  if (mBlock.Kind = 'if') and (mBlock.Branch = 'else') then
  begin
    Result := Result + ', ' + ATexts.ElseBranch;
  end;
end;

function TAtlasWhyHere.LineText(const AFileName: string; ALine: Integer; const ATexts: TAtlasWhyHereTexts): string;
var
  mBlock: Integer;
  mTexts: TArray<string>;
begin
  Result := '';
  if not SameText(AFileName, FFileName) then
  begin
    Exit;
  end;
  mTexts := nil;
  for mBlock := 0 to High(FBlocks) do
  begin
    if FBlocks[mBlock].Line = ALine then
    begin
      mTexts := mTexts + [BlockText(mBlock, ATexts)];
    end;
  end;
  Result := string.Join('  ·  ', mTexts);
end;

end.
