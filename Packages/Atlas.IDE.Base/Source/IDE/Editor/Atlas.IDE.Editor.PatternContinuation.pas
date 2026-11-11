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
    cEnumTimeoutMs = 100;
    /// <summary>Gemerkte Aufzählungen, danach beginnt der Speicher neu.</summary>
    cMaxCachedEnums = 200;
    /// <summary>Nach der Vervollständigung (0), vor Parameterhilfe und Platzhaltern.</summary>
    cKeyPriority = 5;
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
    /// <summary>Atlas an, Vorschau da, keine Vervollständigung offen und AView beschreibbar?</summary>
    class function CanSuggest(const AView: IOTAEditView): Boolean; static;
    /// <summary>Merkt ASuggestion für den Cursor ACursor in AFileName und zeigt den Schattentext; ACurrent ist die
    /// neue, noch leere Zeile.</summary>
    class procedure ShowGhost(const AFileName: string; const ACursor: TOTAEditPos; const ACurrent: string;
      const ASuggestion: TAtlasPatternSuggestion); static;
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
    class procedure EditorModified; static;
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
  cHandlerName = 'PatternContinuation';

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
  begin
    FKeys := TKeys.Create(cKeyPriority);
  end;
  if FEnums = nil then
  begin
    FEnums := TDictionary<string, TArray<string>>.Create;
  end;
  TAtlasEnterWatch.Add(cHandlerName,
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
  TAtlasEnterWatch.Remove(cHandlerName);
  Dismiss;
  // Vor dem Freigeben abmelden (TAtlasKeyHook).
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
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
  begin
    Exit;
  end;
  FFileName := '';
  FSuggestion := Default(TAtlasPatternSuggestion);
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  if FPreview <> nil then
  begin
    FPreview.Clear;
  end;
end;

class procedure TAtlasIdePatternContinuation.EditorModified;
begin
  Dismiss;
end;

class function TAtlasIdePatternContinuation.AtSuggestion: Boolean;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, FFileName) and
    (mView.CursorPos.Line = FLine) and (mView.CursorPos.Col = FColumn);
end;

class function TAtlasIdePatternContinuation.EnumValues(const AFileName, AText, AMember: string;
  ALine, ACharacter: Integer): TArray<string>;
var
  mSession: TLspSession;
  mAnswer: TJSONValue;
  mItem: TJSONValue;
  mKey: string;
begin
  Result := TAtlasPatternContinuation.LocalEnumValues(AText, AMember);
  if Result <> nil then
  begin
    Exit;
  end;
  mKey := LowerCase(AFileName + '|' + AMember);
  if (FEnums <> nil) and FEnums.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  mSession := nil;
  if Assigned(FSessionOf) then
  begin
    mSession := FSessionOf();
  end;
  if (mSession = nil) or not mSession.Initialized then
  begin
    Exit;
  end;
  try
    mSession.Sync(AFileName, AText);
    mAnswer := mSession.RunCommand('atlas.server.enumValues', Format('["%s",{"line":%d,"character":%d}]',
      [TLspSession.PathToUri(AFileName).Replace('\', '\\').Replace('"', '\"'), ALine, ACharacter]), cEnumTimeoutMs);
    try
      if mAnswer is TJSONArray then
      begin
        for mItem in TJSONArray(mAnswer) do
        begin
          Result := Result + [mItem.Value];
        end;
      end;
    finally
      mAnswer.Free;
    end;
  except
    // Zeitlimit oder Fehler: kein Aufzählungswert, also kein Vorschlag für diese Spalte.
    on ELspClientError do
      Result := nil;
  end;
  if FEnums <> nil then
  begin
    if FEnums.Count >= cMaxCachedEnums then
    begin
      FEnums.Clear;
    end;
    FEnums.AddOrSetValue(mKey, Result);
  end;
end;

/// <summary>Enter am Zeilenende: Zeile ALine (0-basiert) ist leer oder nur eingerückt, und Spalte AColumn steht an
/// ihrem Ende.</summary>
function AtEmptyNewLine(const ALines: TArray<string>; ALine, AColumn, ATabWidth: Integer): Boolean;
begin
  Result := (ALine >= 1) and (ALine <= High(ALines)) and (Trim(ALines[ALine]) = '') and
    (TLspSession.ColumnToIndex(ALines[ALine], AColumn, ATabWidth) >= Length(ALines[ALine]));
end;

/// <summary>Ersetzt Zeile ALine (0-basiert) im Puffer ABuffer (Text AText) durch ANewLine; False, wenn es die Zeile
/// nicht gibt.</summary>
function WriteLine(const ABuffer: IOTAEditBuffer; const AText: string; ALine: Integer; const ANewLine: string):
  Boolean;
var
  mLineBreak, mInsert: string;
  mLines: TArray<string>;
  mStart, mOldLength: Integer;
begin
  mLineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  mLines := AText.Split([#13#10, #10]);
  Result := (ALine >= 0) and (ALine <= High(mLines));
  if not Result then
  begin
    Exit;
  end;
  mLines[ALine] := ANewLine;
  if TAtlasLineMover.Difference(AText, string.Join(mLineBreak, mLines), mStart, mOldLength, mInsert) then
  begin
    TAtlasEditorSnapshots.ReplaceText(ABuffer, AText, mStart, mOldLength, mInsert);
  end;
end;

class function TAtlasIdePatternContinuation.CanSuggest(const AView: IOTAEditView): Boolean;
begin
  Result := Enabled and (AView <> nil) and (AView.Buffer <> nil) and (FPreview <> nil);
  if Result and Assigned(FCompletionVisible) then
  begin
    Result := not FCompletionVisible();
  end;
  Result := Result and not AView.Buffer.IsReadOnly;
end;

class procedure TAtlasIdePatternContinuation.ShowGhost(const AFileName: string; const ACursor: TOTAEditPos;
  const ACurrent: string; const ASuggestion: TAtlasPatternSuggestion);
var
  mGhost: string;
begin
  // Schattentext ab dem Cursor: was am Einzug noch fehlt, dann die Zeile.
  mGhost := ASuggestion.Text;
  if ASuggestion.Indent.StartsWith(ACurrent) then
  begin
    mGhost := Copy(ASuggestion.Indent, Length(ACurrent) + 1, MaxInt) + mGhost;
  end;
  FFileName := AFileName;
  FLine := ACursor.Line;
  FColumn := ACursor.Col;
  FSuggestion := ASuggestion;
  TAtlasKeyHook.Add(FKeys);
  FPreview.Show(AFileName, ACursor.Line, ACursor.Col, mGhost);
end;

class function TAtlasIdePatternContinuation.Run(const AView: IOTAEditView): Boolean;
var
  mFileName, mText: string;
  mLines: TArray<string>;
  mCursor: TOTAEditPos;
  mLine: Integer;
  mSuggestion: TAtlasPatternSuggestion;
begin
  Result := False;
  Dismiss;
  if not CanSuggest(AView) then
  begin
    Exit;
  end;
  mFileName := AView.Buffer.FileName;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  mCursor := AView.CursorPos;
  mLine := mCursor.Line - 1;
  if not AtEmptyNewLine(mLines, mLine, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)) then
  begin
    Exit;
  end;
  if not TAtlasPatternContinuation.Suggest(mLines, mLine, TAtlasIdeSettings.Current.ContinuePatternMinLines,
    function(const AMember: string; ALine, ACharacter: Integer): TArray<string>
    begin
      Result := EnumValues(mFileName, mText, AMember, ALine, ACharacter);
    end,
    function(const AName: string): Boolean
    begin
      Result := TAtlasPatternContinuation.ContainsWord(mText, AName);
    end, mSuggestion) then
  begin
    Exit;
  end;
  ShowGhost(mFileName, mCursor, mLines[mLine], mSuggestion);
  // Den Zeilenumbruch hat die IDE schon geschrieben; „übernommen“ heißt hier nur: nichts weiter versuchen.
  Result := True;
end;

class procedure TAtlasIdePatternContinuation.Accept;
var
  mView: IOTAEditView;
  mBuffer: IOTAEditBuffer;
  mNewLine: string;
  mSuggestion: TAtlasPatternSuggestion;
  mTarget: TOTAEditPos;
  mLine, mCharacter: Integer;
begin
  if not Visible or not AtSuggestion then
  begin
    Dismiss;
    Exit;
  end;
  mSuggestion := FSuggestion;
  mLine := FLine - 1;
  // Erst verwerfen: Das Schreiben ist selbst eine Änderung.
  Dismiss;
  mView := TAtlasEditorBuffer.ActiveView;
  mBuffer := mView.Buffer;
  mNewLine := mSuggestion.Indent + mSuggestion.Text;
  if mBuffer.IsReadOnly or not WriteLine(mBuffer, TAtlasEditorBuffer.Text(mBuffer), mLine, mNewLine) then
  begin
    Exit;
  end;
  mCharacter := Length(mNewLine);
  if Length(mSuggestion.Fields) > 0 then
  begin
    mCharacter := Length(mSuggestion.Indent) + mSuggestion.Fields[0];
  end;
  mTarget.Line := mLine + 1;
  mTarget.Col := TLspSession.IndexToColumn(mNewLine, mCharacter, TAtlasEditorBuffer.TabWidth(mBuffer));
  mView.CursorPos := mTarget;
  mView.MoveViewToCursor;
  mView.Paint;
end;

end.
