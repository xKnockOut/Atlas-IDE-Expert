unit Atlas.Core.Editor.MethodPlacement;

// Methodenrümpfe in Deklarationsreihenfolge (#660), Kern im Plugin ohne VCL
// und ToolsAPI: Argumente für atlas.server.methodOrder, die Antwort als
// Datensatz, die Zeilen der Vorschau und was das Plugin nach einer
// Klassenvervollständigung braucht:
// - NewHeaders prüft billig, ob seit dem letzten Stand ein Methodenkopf
//   (procedure TFoo.Bar …) dazugekommen ist; nur dann fragt das Plugin den
//   Server.
// - Difference liefert die eine Änderung vom Stand vor der
//   Klassenvervollständigung zum Ergebnis; so bleibt beides ein
//   Rückgängig-Schritt.
// - CaretLine nimmt die Schreibmarke im verschobenen Rumpf mit.
// Vorschau: je verschobenem Rumpf "↑ 3  TKunde.Speichern", je stehen
// bleibendem "bleibt: in einer Region  TKunde.Laden".

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TAtlasMethodMove = record
    TypeName: string;
    Name: string;
    /// <summary>Kopfzeile vorher und nachher (ab 0); NewLine -1 bei stehen bleibenden.</summary>
    Line: Integer;
    NewLine: Integer;
    /// <summary>Zeilen vom Kopf bis zum end.</summary>
    Size: Integer;
    /// <summary>Verschiebung in Rümpfen; negativ = nach oben.</summary>
    Delta: Integer;
    Fixed: Boolean;
    /// <summary>region, ifdef, line oder ''.</summary>
    Reason: string;
  end;

  TAtlasMethodPlacementReply = record
    Edits: TArray<TLspTextEdit>;
    Moves: TArray<TAtlasMethodMove>;
    /// <summary>Verschobene Rümpfe (ohne die stehen bleibenden).</summary>
    function Moved: Integer;
  end;

  /// <summary>Texte der Vorschau, aus Atlas.UI.Strings.</summary>
  TAtlasMethodPlacementTexts = record
    /// <summary>Mit %d: "↑ %d", "↓ %d".</summary>
    Up: string;
    Down: string;
    /// <summary>Mit %s für den Grund: "bleibt: %s".</summary>
    Stays: string;
    Region: string;
    Conditional: string;
    SharedLine: string;
  end;

  TAtlasMethodPlacement = class
  public const
    Command = 'atlas.server.methodOrder';
    /// <summary>Ruhezeit nach der letzten Änderung, bevor das Plugin nach neuen Rümpfen sieht.</summary>
    DelayMs = 400;
  public
    /// <summary>[uri, {mode, scope, before}]; AAll: ganze Unit ordnen, sonst nur die gegenüber ABefore neuen
    /// Rümpfe.</summary>
    class function Arguments(const AUri, AMode: string; AAll: Boolean; const ABefore: string): string; static;
    /// <summary>False, wenn die Antwort nicht lesbar ist.</summary>
    class function Read(const AAnswer: TJSONValue; out AReply: TAtlasMethodPlacementReply): Boolean; static;
    /// <summary>Steht in AAfter ein Methodenkopf mit Typ (procedure TFoo.Bar), der in ABefore fehlt?</summary>
    class function NewHeaders(const ABefore, AAfter: string): Boolean; static;
    /// <summary>Die eine Änderung von AOld zu ANew (gemeinsamer Anfang und gemeinsames Ende bleiben); False bei
    /// gleichem Text.</summary>
    class function Difference(const AOld, ANew: string; out ARange: TLspTextRange): Boolean; static;
    /// <summary>Neue Zeile der Schreibmarke ALine, wenn sie in einem verschobenen Rumpf steht.</summary>
    class function CaretLine(const AMoves: TArray<TAtlasMethodMove>; ALine: Integer; out ANewLine: Integer): Boolean;
      static;
    /// <summary>Zeile der Vorschau.</summary>
    class function MoveText(const AMove: TAtlasMethodMove; const ATexts: TAtlasMethodPlacementTexts): string;
      static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines;

const
  cRoutineWords: array[0..6] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ',
    'class procedure ', 'class function ');

function IntegerOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  if AObject.GetValue(AName) is TJSONNumber then
  begin
    Result := TJSONNumber(AObject.GetValue(AName)).AsInt;
  end;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
  begin
    Result := TJSONString(AObject.GetValue(AName)).Value;
  end;
end;

/// <summary>Kopf einer Methode mit Typ: "procedure TFoo.Bar", auch class procedure und constructor.</summary>
function IsMethodHeader(const ALine: string): Boolean;
var
  mLower, mWord: string;
  mStop: Integer;
begin
  Result := False;
  mLower := LowerCase(Trim(ALine));
  for mWord in cRoutineWords do
  begin
    if StartsStr(mWord, mLower) then
    begin
      mStop := Length(mLower) + 1;
      if Pos('(', mLower) > 0 then
      begin
        mStop := Pos('(', mLower);
      end;
      if (Pos(';', mLower) > 0) and (Pos(';', mLower) < mStop) then
      begin
        mStop := Pos(';', mLower);
      end;
      Exit(Pos('.', Copy(mLower, Length(mWord) + 1, mStop - Length(mWord) - 1)) > 0);
    end;
  end;
end;

{ TAtlasMethodPlacementReply }

function TAtlasMethodPlacementReply.Moved: Integer;
var
  mMove: TAtlasMethodMove;
begin
  Result := 0;
  for mMove in Moves do
  begin
    if not mMove.Fixed then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasMethodPlacement }

class function TAtlasMethodPlacement.Arguments(const AUri, AMode: string; AAll: Boolean;
  const ABefore: string): string;
var
  mList: TJSONArray;
  mOptions: TJSONObject;
begin
  mList := TJSONArray.Create;
  try
    mList.Add(AUri);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('mode', AMode);
    if AAll then
    begin
      mOptions.AddPair('scope', 'all');
    end
    else
    begin
      mOptions.AddPair('scope', 'new');
      mOptions.AddPair('before', ABefore);
    end;
    mList.AddElement(mOptions);
    Result := mList.ToJSON;
  finally
    mList.Free;
  end;
end;

class function TAtlasMethodPlacement.Read(const AAnswer: TJSONValue; out AReply: TAtlasMethodPlacementReply): Boolean;
var
  mAnswer, mItem: TJSONObject;
  mElement: TJSONValue;
  mEdit: TLspTextEdit;
  mMove: TAtlasMethodMove;
begin
  AReply := Default(TAtlasMethodPlacementReply);
  Result := AAnswer is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  mAnswer := TJSONObject(AAnswer);
  if mAnswer.GetValue('edits') is TJSONArray then
  begin
    for mElement in TJSONArray(mAnswer.GetValue('edits')) do
    begin
      if TLspTextEdit.FromJson(mElement, mEdit) then
      begin
        AReply.Edits := AReply.Edits + [mEdit];
      end;
    end;
  end;
  if mAnswer.GetValue('moves') is TJSONArray then
  begin
    for mElement in TJSONArray(mAnswer.GetValue('moves')) do
    begin
      if not (mElement is TJSONObject) then
      begin
        Continue;
      end;
      mItem := TJSONObject(mElement);
      mMove := Default(TAtlasMethodMove);
      mMove.TypeName := StringOf(mItem, 'type');
      mMove.Name := StringOf(mItem, 'name');
      mMove.Line := IntegerOf(mItem, 'line', 0);
      mMove.NewLine := IntegerOf(mItem, 'newLine', -1);
      mMove.Size := IntegerOf(mItem, 'size', 1);
      mMove.Delta := IntegerOf(mItem, 'delta', 0);
      mMove.Fixed := (mItem.GetValue('fixed') is TJSONBool) and TJSONBool(mItem.GetValue('fixed')).AsBoolean;
      mMove.Reason := StringOf(mItem, 'reason');
      AReply.Moves := AReply.Moves + [mMove];
    end;
  end;
end;

class function TAtlasMethodPlacement.NewHeaders(const ABefore, AAfter: string): Boolean;
var
  mKnown: TDictionary<string, Boolean>;
  mLine: string;
begin
  Result := False;
  if ABefore = AAfter then
  begin
    Exit;
  end;
  mKnown := TDictionary<string, Boolean>.Create;
  try
    for mLine in TTextLines.SplitLines(ABefore) do
    begin
      if IsMethodHeader(mLine) then
      begin
        mKnown.AddOrSetValue(Trim(mLine), True);
      end;
    end;
    for mLine in TTextLines.SplitLines(AAfter) do
    begin
      if IsMethodHeader(mLine) and not mKnown.ContainsKey(Trim(mLine)) then
      begin
        Exit(True);
      end;
    end;
  finally
    mKnown.Free;
  end;
end;

/// <summary>Erste Hälfte eines Zeilenumbruchs #13#10 oder eines Ersatzpaars: dort nicht schneiden.</summary>
function IsLeadingHalf(AChar: Char): Boolean;
begin
  Result := (AChar = #13) or ((AChar >= #$D800) and (AChar <= #$DBFF));
end;

/// <summary>Zweite Hälfte eines Zeilenumbruchs #13#10 oder eines Ersatzpaars.</summary>
function IsTrailingHalf(AChar: Char): Boolean;
begin
  Result := (AChar = #10) or ((AChar >= #$DC00) and (AChar <= #$DFFF));
end;

/// <summary>Länge des gemeinsamen Anfangs.</summary>
function CommonPrefix(const AOld, ANew: string): Integer;
begin
  Result := 0;
  while (Result < Length(AOld)) and (Result < Length(ANew)) and (AOld[Result + 1] = ANew[Result + 1]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Länge des gemeinsamen Endes, ohne in APrefix hineinzureichen.</summary>
function CommonSuffix(const AOld, ANew: string; APrefix: Integer): Integer;
begin
  Result := 0;
  while (Result < Length(AOld) - APrefix) and (Result < Length(ANew) - APrefix) and
    (AOld[Length(AOld) - Result] = ANew[Length(ANew) - Result]) do
  begin
    Inc(Result);
  end;
end;

class function TAtlasMethodPlacement.Difference(const AOld, ANew: string; out ARange: TLspTextRange): Boolean;
var
  mPrefix, mSuffix: Integer;
begin
  ARange := Default(TLspTextRange);
  Result := AOld <> ANew;
  if Result then
  begin
    mPrefix := CommonPrefix(AOld, ANew);
    mSuffix := CommonSuffix(AOld, ANew, mPrefix);
    // Kein Schnitt mitten in einem Zeilenumbruch #13#10 oder einem Ersatzpaar.
    while (mPrefix > 0) and IsLeadingHalf(AOld[mPrefix]) do
    begin
      Dec(mPrefix);
    end;
    while (mSuffix > 0) and IsTrailingHalf(AOld[Length(AOld) - mSuffix + 1]) do
    begin
      Dec(mSuffix);
    end;
    ARange.StartOffset := mPrefix;
    ARange.EndOffset := Length(AOld) - mSuffix;
    ARange.NewText := Copy(ANew, mPrefix + 1, Length(ANew) - mSuffix - mPrefix);
  end;
end;

class function TAtlasMethodPlacement.CaretLine(const AMoves: TArray<TAtlasMethodMove>; ALine: Integer;
  out ANewLine: Integer): Boolean;
var
  mMove: TAtlasMethodMove;
begin
  ANewLine := ALine;
  for mMove in AMoves do
  begin
    if not mMove.Fixed and (mMove.NewLine >= 0) and (ALine >= mMove.Line) and (ALine < mMove.Line + mMove.Size) then
    begin
      ANewLine := mMove.NewLine + ALine - mMove.Line;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasMethodPlacement.MoveText(const AMove: TAtlasMethodMove;
  const ATexts: TAtlasMethodPlacementTexts): string;
var
  mReason: string;
begin
  if AMove.Fixed then
  begin
    mReason := ATexts.SharedLine;
    if AMove.Reason = 'region' then
    begin
      mReason := ATexts.Region;
    end
    else if AMove.Reason = 'ifdef' then
    begin
      mReason := ATexts.Conditional;
    end;
    Result := Format(ATexts.Stays, [mReason]);
  end
  else if AMove.Delta < 0 then
  begin
    Result := Format(ATexts.Up, [-AMove.Delta]);
  end
  else
  begin
    Result := Format(ATexts.Down, [AMove.Delta]);
  end;
  Result := Result + '  ' + AMove.TypeName + '.' + AMove.Name;
end;

end.
