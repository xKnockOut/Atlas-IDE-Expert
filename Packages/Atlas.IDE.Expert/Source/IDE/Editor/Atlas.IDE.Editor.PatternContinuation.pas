unit Atlas.IDE.Editor.PatternContinuation;

// Muster fortsetzen (#671) im Editor: Nach Enter am Ende einer Zeile schlägt
// Atlas die nächste Zeile eines erkannten Musters als Schattentext vor. Was
// vorgeschlagen wird, rechnet Atlas.Core.Editor.PatternContinuation aus; hier
// bleiben Auslöser, Anzeige, Tab und Puffer.
// - Auslöser ist Atlas.IDE.Editor.EnterWatch (nach „Kommentar fortsetzen“).
//   Kein Vorschlag, solange die Vervollständigung offen ist.
// - Aufzählungswerte: erst aus der Datei selbst, sonst vom Server
//   (atlas.server.enumValues, kurzes Zeitlimit, je Datei und Wert gemerkt).
//   Nummerierte Bezeichner gelten, wenn der neue Name in der Datei vorkommt.
// - Anzeige über TAtlasEditorPreview (Element PatternPreview), nur solange der
//   Cursor in der Zeile steht.
// - Tab ist nur belegt, solange ein Vorschlag sichtbar ist und der Cursor an
//   seiner Stelle steht: Atlas schreibt die Zeile als einen Rückgängig-Schritt
//   und setzt den Cursor ins erste freie Feld (zwischen leere Hochkommas),
//   sonst ans Zeilenende. Jede andere Änderung und jeder Wechsel der Ansicht
//   verwirft den Vorschlag; das Zeichen wird normal getippt.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.PatternContinuation,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Completion.Preview;

type
  TAtlasIdePatternContinuation = class
  private const
    /// <summary>Höchstens so lange wartet Enter auf die Werte eines Aufzählungstyps vom Server.</summary>
    EnumTimeoutMs = 100;
    /// <summary>Gemerkte Aufzählungen, danach beginnt der Speicher neu.</summary>
    MaxCachedEnums = 200;
    /// <summary>Nach der Vervollständigung (0), vor Parameterhilfe und Platzhaltern.</summary>
    KeyPriority = 5;
  private type
    TKeys = class(TAtlasKeyClient)
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    end;
  private class var
    FSessionOf: TFunc<TLspSession>;
    FCompletionVisible: TFunc<Boolean>;
    FPreview: TAtlasEditorPreview;
    FKeys: TKeys;
    FEnums: TDictionary<string, TArray<string>>;
    /// <summary>Sichtbarer Vorschlag: Datei, Zeile und Spalte des Cursors (1-basiert), Vorschlag.</summary>
    FFileName: string;
    FLine: Integer;
    FColumn: Integer;
    FSuggestion: TAtlasPatternSuggestion;
    class function Run(const AView: IOTAEditView): Boolean; static;
    class function EnumValues(const AFileName, AText, AMember: string; ALine, ACharacter: Integer): TArray<string>;
      static;
    /// <summary>Steht der Cursor der oberen Ansicht noch dort, wo der Vorschlag gezeigt wird?</summary>
    class function AtSuggestion: Boolean; static;
    class procedure Accept; static;
  public
    /// <summary>ASessionOf liefert die Sitzung oder nil; ACompletionVisible: ist die Vervollständigung offen?
    /// </summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const ACompletionVisible: TFunc<Boolean>);
      static;
    class procedure Uninstall; static;
    /// <summary>editor.continuePattern an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    class function Visible: Boolean; static;
    /// <summary>Vorschlag verwerfen.</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: jede Änderung verwirft einen sichtbaren Vorschlag.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.JSON,
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Editor.EnterWatch;

const
  HandlerName = 'PatternContinuation';

/// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert; ein eigener
/// Rückgängig-Schritt.</summary>
procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string; AStart, AOldLength: Integer;
  const AInsert: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart)));
  Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart + AOldLength)));
  if AInsert <> '' then
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

{ TAtlasIdePatternContinuation.TKeys }

function TAtlasIdePatternContinuation.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (AKey = VK_TAB) and (AShift = []) and Visible and AtSuggestion;
end;

procedure TAtlasIdePatternContinuation.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  TAtlasGuard.Run(TAtlasFeature.ContinueLines,
    procedure
    begin
      Accept;
    end);
end;

{ TAtlasIdePatternContinuation }

class procedure TAtlasIdePatternContinuation.Install(const ASessionOf: TFunc<TLspSession>;
  const ACompletionVisible: TFunc<Boolean>);
begin
  FSessionOf := ASessionOf;
  FCompletionVisible := ACompletionVisible;
  if FPreview = nil then
  begin
    FPreview := TAtlasEditorPreview.Create;
    FPreview.Element := TAtlasDrawnElement.PatternPreview;
    FPreview.FollowCursor := True;
  end;
  if FKeys = nil then
    FKeys := TKeys.Create(KeyPriority);
  if FEnums = nil then
    FEnums := TDictionary<string, TArray<string>>.Create;
  TAtlasEnterWatch.Add(HandlerName,
    function: Boolean
    begin
      Result := Enabled;
    end,
    function(const AView: IOTAEditView): Boolean
    begin
      Result := Run(AView);
    end);
end;

class procedure TAtlasIdePatternContinuation.Uninstall;
begin
  TAtlasEnterWatch.Remove(HandlerName);
  Dismiss;
  // Vor dem Freigeben abmelden (TAtlasKeyHook).
  if FKeys <> nil then
    TAtlasKeyHook.Remove(FKeys);
  FreeAndNil(FKeys);
  FreeAndNil(FPreview);
  FreeAndNil(FEnums);
  FSessionOf := nil;
  FCompletionVisible := nil;
end;

class function TAtlasIdePatternContinuation.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.ContinuePattern;
end;

class function TAtlasIdePatternContinuation.Visible: Boolean;
begin
  Result := FFileName <> '';
end;

class procedure TAtlasIdePatternContinuation.Dismiss;
begin
  if FFileName = '' then
    Exit;
  FFileName := '';
  FSuggestion := Default(TAtlasPatternSuggestion);
  if FKeys <> nil then
    TAtlasKeyHook.Remove(FKeys);
  if FPreview <> nil then
    FPreview.Clear;
end;

class procedure TAtlasIdePatternContinuation.EditorModified(const AView: IOTAEditView);
begin
  Dismiss;
end;

class function TAtlasIdePatternContinuation.AtSuggestion: Boolean;
var
  View: IOTAEditView;
begin
  View := TAtlasEditorBuffer.ActiveView;
  Result := (View <> nil) and (View.Buffer <> nil) and SameText(View.Buffer.FileName, FFileName) and
    (View.CursorPos.Line = FLine) and (View.CursorPos.Col = FColumn);
end;

class function TAtlasIdePatternContinuation.EnumValues(const AFileName, AText, AMember: string;
  ALine, ACharacter: Integer): TArray<string>;
var
  Session: TLspSession;
  Answer: TJSONValue;
  Item: TJSONValue;
  Key: string;
begin
  Result := TAtlasPatternContinuation.LocalEnumValues(AText, AMember);
  if Result <> nil then
    Exit;
  Key := LowerCase(AFileName + '|' + AMember);
  if (FEnums <> nil) and FEnums.TryGetValue(Key, Result) then
    Exit;
  Session := nil;
  if Assigned(FSessionOf) then
    Session := FSessionOf();
  if (Session = nil) or not Session.Initialized then
    Exit;
  try
    Session.Sync(AFileName, AText);
    Answer := Session.RunCommand('atlas.server.enumValues', Format('["%s",{"line":%d,"character":%d}]',
      [TLspSession.PathToUri(AFileName).Replace('\', '\\').Replace('"', '\"'), ALine, ACharacter]), EnumTimeoutMs);
    try
      if Answer is TJSONArray then
        for Item in TJSONArray(Answer) do
          Result := Result + [Item.Value];
    finally
      Answer.Free;
    end;
  except
    // Zeitlimit oder Fehler: kein Aufzählungswert, also kein Vorschlag für diese Spalte.
    on ELspClientError do
      Result := nil;
  end;
  if FEnums <> nil then
  begin
    if FEnums.Count >= MaxCachedEnums then
      FEnums.Clear;
    FEnums.AddOrSetValue(Key, Result);
  end;
end;

class function TAtlasIdePatternContinuation.Run(const AView: IOTAEditView): Boolean;
var
  Buffer: IOTAEditBuffer;
  FileName, Text, Current, Ghost: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  Line, Character: Integer;
  Suggestion: TAtlasPatternSuggestion;
begin
  Result := False;
  Dismiss;
  if not Enabled or (AView = nil) or (AView.Buffer = nil) or (FPreview = nil) then
    Exit;
  if Assigned(FCompletionVisible) and FCompletionVisible() then
    Exit;
  Buffer := AView.Buffer;
  if Buffer.IsReadOnly then
    Exit;
  FileName := Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(Buffer);
  Lines := Text.Split([#13#10, #10]);
  Cursor := AView.CursorPos;
  Line := Cursor.Line - 1;
  if (Line < 1) or (Line > High(Lines)) then
    Exit;
  // Enter am Zeilenende: die neue Zeile ist leer oder nur eingerückt, der Cursor steht an ihrem Ende.
  Current := Lines[Line];
  Character := TLspSession.ColumnToIndex(Current, Cursor.Col, TAtlasEditorBuffer.TabWidth(Buffer));
  if (Trim(Current) <> '') or (Character < Length(Current)) then
    Exit;
  if not TAtlasPatternContinuation.Suggest(Lines, Line, TAtlasIdeSettings.Current.ContinuePatternMinLines,
    function(const AMember: string; ALine, ACharacter: Integer): TArray<string>
    begin
      Result := EnumValues(FileName, Text, AMember, ALine, ACharacter);
    end,
    function(const AName: string): Boolean
    begin
      Result := TAtlasPatternContinuation.ContainsWord(Text, AName);
    end, Suggestion) then
    Exit;
  // Schattentext ab dem Cursor: was am Einzug noch fehlt, dann die Zeile.
  Ghost := Suggestion.Text;
  if Suggestion.Indent.StartsWith(Current) then
    Ghost := Copy(Suggestion.Indent, Length(Current) + 1, MaxInt) + Ghost;
  FFileName := FileName;
  FLine := Cursor.Line;
  FColumn := Cursor.Col;
  FSuggestion := Suggestion;
  TAtlasKeyHook.Add(FKeys);
  FPreview.Show(FileName, Cursor.Line, Cursor.Col, Ghost);
  // Den Zeilenumbruch hat die IDE schon geschrieben; „übernommen“ heißt hier nur: nichts weiter versuchen.
  Result := True;
end;

class procedure TAtlasIdePatternContinuation.Accept;
var
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Text, LineBreak, NewText, Insert, NewLine: string;
  Lines: TArray<string>;
  Suggestion: TAtlasPatternSuggestion;
  Target: TOTAEditPos;
  Line, Start, OldLength, Character: Integer;
begin
  if not Visible or not AtSuggestion then
  begin
    Dismiss;
    Exit;
  end;
  Suggestion := FSuggestion;
  Line := FLine - 1;
  // Erst verwerfen: Das Schreiben ist selbst eine Änderung.
  Dismiss;
  View := TAtlasEditorBuffer.ActiveView;
  Buffer := View.Buffer;
  if Buffer.IsReadOnly then
    Exit;
  Text := TAtlasEditorBuffer.Text(Buffer);
  LineBreak := #10;
  if Pos(#13#10, Text) > 0 then
    LineBreak := #13#10;
  Lines := Text.Split([#13#10, #10]);
  if (Line < 0) or (Line > High(Lines)) then
    Exit;
  NewLine := Suggestion.Indent + Suggestion.Text;
  Lines[Line] := NewLine;
  NewText := string.Join(LineBreak, Lines);
  if TAtlasLineMover.Difference(Text, NewText, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Text, Start, OldLength, Insert);
  Character := Length(NewLine);
  if Length(Suggestion.Fields) > 0 then
    Character := Length(Suggestion.Indent) + Suggestion.Fields[0];
  Target.Line := Line + 1;
  Target.Col := TLspSession.IndexToColumn(NewLine, Character, TAtlasEditorBuffer.TabWidth(Buffer));
  View.CursorPos := Target;
  View.MoveViewToCursor;
  View.Paint;
end;

end.
