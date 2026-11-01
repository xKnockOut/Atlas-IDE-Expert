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
  RoutineWords: array[0..6] of string = ('procedure ', 'function ', 'constructor ', 'destructor ', 'operator ',
    'class procedure ', 'class function ');

function IntegerOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  if AObject.GetValue(AName) is TJSONNumber then
    Result := TJSONNumber(AObject.GetValue(AName)).AsInt;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
    Result := TJSONString(AObject.GetValue(AName)).Value;
end;

/// <summary>Kopf einer Methode mit Typ: "procedure TFoo.Bar", auch class procedure und constructor.</summary>
function IsMethodHeader(const ALine: string): Boolean;
var
  Lower, Word: string;
  Stop: Integer;
begin
  Result := False;
  Lower := LowerCase(Trim(ALine));
  for Word in RoutineWords do
    if StartsStr(Word, Lower) then
    begin
      Stop := Length(Lower) + 1;
      if Pos('(', Lower) > 0 then
        Stop := Pos('(', Lower);
      if (Pos(';', Lower) > 0) and (Pos(';', Lower) < Stop) then
        Stop := Pos(';', Lower);
      Exit(Pos('.', Copy(Lower, Length(Word) + 1, Stop - Length(Word) - 1)) > 0);
    end;
end;

{ TAtlasMethodPlacementReply }

function TAtlasMethodPlacementReply.Moved: Integer;
var
  Move: TAtlasMethodMove;
begin
  Result := 0;
  for Move in Moves do
    if not Move.Fixed then
      Inc(Result);
end;

{ TAtlasMethodPlacement }

class function TAtlasMethodPlacement.Arguments(const AUri, AMode: string; AAll: Boolean;
  const ABefore: string): string;
var
  List: TJSONArray;
  Options: TJSONObject;
begin
  List := TJSONArray.Create;
  try
    List.Add(AUri);
    Options := TJSONObject.Create;
    Options.AddPair('mode', AMode);
    if AAll then
      Options.AddPair('scope', 'all')
    else
    begin
      Options.AddPair('scope', 'new');
      Options.AddPair('before', ABefore);
    end;
    List.AddElement(Options);
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

class function TAtlasMethodPlacement.Read(const AAnswer: TJSONValue; out AReply: TAtlasMethodPlacementReply): Boolean;
var
  Answer, Item: TJSONObject;
  Element: TJSONValue;
  Edit: TLspTextEdit;
  Move: TAtlasMethodMove;
begin
  AReply := Default(TAtlasMethodPlacementReply);
  Result := AAnswer is TJSONObject;
  if not Result then
    Exit;
  Answer := TJSONObject(AAnswer);
  if Answer.GetValue('edits') is TJSONArray then
    for Element in TJSONArray(Answer.GetValue('edits')) do
      if TLspTextEdit.FromJson(Element, Edit) then
        AReply.Edits := AReply.Edits + [Edit];
  if Answer.GetValue('moves') is TJSONArray then
    for Element in TJSONArray(Answer.GetValue('moves')) do
    begin
      if not (Element is TJSONObject) then
        Continue;
      Item := TJSONObject(Element);
      Move := Default(TAtlasMethodMove);
      Move.TypeName := StringOf(Item, 'type');
      Move.Name := StringOf(Item, 'name');
      Move.Line := IntegerOf(Item, 'line', 0);
      Move.NewLine := IntegerOf(Item, 'newLine', -1);
      Move.Size := IntegerOf(Item, 'size', 1);
      Move.Delta := IntegerOf(Item, 'delta', 0);
      Move.Fixed := (Item.GetValue('fixed') is TJSONBool) and TJSONBool(Item.GetValue('fixed')).AsBoolean;
      Move.Reason := StringOf(Item, 'reason');
      AReply.Moves := AReply.Moves + [Move];
    end;
end;

class function TAtlasMethodPlacement.NewHeaders(const ABefore, AAfter: string): Boolean;
var
  Known: TDictionary<string, Boolean>;
  Line: string;
begin
  Result := False;
  if ABefore = AAfter then
    Exit;
  Known := TDictionary<string, Boolean>.Create;
  try
    for Line in TTextLines.SplitLines(ABefore) do
      if IsMethodHeader(Line) then
        Known.AddOrSetValue(Trim(Line), True);
    for Line in TTextLines.SplitLines(AAfter) do
      if IsMethodHeader(Line) and not Known.ContainsKey(Trim(Line)) then
        Exit(True);
  finally
    Known.Free;
  end;
end;

class function TAtlasMethodPlacement.Difference(const AOld, ANew: string; out ARange: TLspTextRange): Boolean;
var
  Prefix, Suffix: Integer;
begin
  ARange := Default(TLspTextRange);
  Result := AOld <> ANew;
  if not Result then
    Exit;
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
    Inc(Suffix);
  // Kein Schnitt mitten in einem Zeilenumbruch #13#10 oder einem Ersatzpaar.
  while (Prefix > 0) and ((AOld[Prefix] = #13) or ((AOld[Prefix] >= #$D800) and (AOld[Prefix] <= #$DBFF))) do
    Dec(Prefix);
  while (Suffix > 0) and ((AOld[Length(AOld) - Suffix + 1] = #10) or
    ((AOld[Length(AOld) - Suffix + 1] >= #$DC00) and (AOld[Length(AOld) - Suffix + 1] <= #$DFFF))) do
    Dec(Suffix);
  ARange.StartOffset := Prefix;
  ARange.EndOffset := Length(AOld) - Suffix;
  ARange.NewText := Copy(ANew, Prefix + 1, Length(ANew) - Suffix - Prefix);
end;

class function TAtlasMethodPlacement.CaretLine(const AMoves: TArray<TAtlasMethodMove>; ALine: Integer;
  out ANewLine: Integer): Boolean;
var
  Move: TAtlasMethodMove;
begin
  ANewLine := ALine;
  for Move in AMoves do
    if not Move.Fixed and (Move.NewLine >= 0) and (ALine >= Move.Line) and (ALine < Move.Line + Move.Size) then
    begin
      ANewLine := Move.NewLine + ALine - Move.Line;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasMethodPlacement.MoveText(const AMove: TAtlasMethodMove;
  const ATexts: TAtlasMethodPlacementTexts): string;
var
  Reason: string;
begin
  if AMove.Fixed then
  begin
    Reason := ATexts.SharedLine;
    if AMove.Reason = 'region' then
      Reason := ATexts.Region
    else if AMove.Reason = 'ifdef' then
      Reason := ATexts.Conditional;
    Result := Format(ATexts.Stays, [Reason]);
  end
  else if AMove.Delta < 0 then
    Result := Format(ATexts.Up, [-AMove.Delta])
  else
    Result := Format(ATexts.Down, [AMove.Delta]);
  Result := Result + '  ' + AMove.TypeName + '.' + AMove.Name;
end;

end.
