unit Atlas.IDE.CodeInsight.Manager.Queries;

// Fragen des Code Insight-Managers an den Editor: Welche Code Insight löst eine Taste aus (Vervollständigung nach
// ".", Parameterhilfe nach "(", XMLDoc-Tags nach "<" in ///-Zeilen #435, Mengen nach "[" #448, try…finally nach ";"
// #489, Mitglieder nach "{" in Wertdarstellungen #854, Feldnamen nach ' in FieldByName #461)? Dazu Symbolhinweis
// (GetHintText, mit Wert im angehaltenen Debugger #891) und Gehe zu Definition für die Cursorposition.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session;

type
  /// <summary>Editorposition, Auslöser und Antworten des Servers für die Einstiegspunkte der IDE.</summary>
  TAtlasCodeInsightQueries = record
  public
    /// <summary>Editoransicht, in der Code Insight gerade läuft, sonst die oberste.</summary>
    class function CurrentEditView: IOTAEditView; static;
    /// <summary>Cursorzeile ist ein ///-Kommentar (XMLDoc, #435).</summary>
    class function InXmlDocLine: Boolean; static;
    /// <summary>Cursorzeile ist eine Wertdarstellung (// atlas-debug:, [AtlasDebugDisplay], #854).</summary>
    class function InDebugDisplayLine: Boolean; static;
    /// <summary>Cursor im Namen von FieldByName('…'), FindField('…') oder ParamByName('…') (#461).
    /// ATypedQuote: Das gerade getippte ' steht vielleicht noch nicht im Puffer.</summary>
    class function InDataNameString(ATypedQuote: Boolean): Boolean; static;
    /// <summary>Code Insight zu Taste AChar im Element AElement (atComment, atString …); AGuardPending fragt nach
    /// „Mit try…finally absichern“ (#489).</summary>
    class function InsightType(AChar: Char; AElement: Integer; const AGuardPending: TFunc<Boolean>;
      out AInvoke: TOTAInvokeType): TOTACodeInsightType; static;
    /// <summary>Hover-Text an Zeile AHintLine, Spalte AHintCol (1-basiert) von AView; '' außerhalb des Puffers.
    /// </summary>
    class function HintAt(ASession: TLspSession; const AView: IOTAEditView; AHintLine, AHintCol: Integer;
      const ADiagnose: TProc<string>): string; static;
    /// <summary>Definition des Bezeichners an ALine, ACharacter (0-basiert) in AView; False ohne Definition oder mit
    /// einer Ersatz-Unit des Servers (atlas-ide:…), die es nicht als Datei gibt.</summary>
    class function DefinitionOf(ASession: TLspSession; const AView: IOTAEditView; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean; static;
    /// <summary>Definition am Cursor von AView; AFileName = '' ohne Definition.</summary>
    class procedure DefinitionAt(ASession: TLspSession; const AView: IOTAEditView; AIndex: Integer;
      const ADiagnose: TProc<string>; out AFileName: string; out ALineNum: Integer); static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.DebugDisplay,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Completion.Word,
  Atlas.Core.Lsp.IdeMembers,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Hover.DebugValue;

class function TAtlasCodeInsightQueries.CurrentEditView: IOTAEditView;
var
  mServices: IOTACodeInsightServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
  begin
    mServices.GetEditView(Result);
  end;
  if Result = nil then
  begin
    Result := (BorlandIDEServices as IOTAEditorServices).TopView;
  end;
end;

class function TAtlasCodeInsightQueries.InXmlDocLine: Boolean;
var
  mView: IOTAEditView;
begin
  mView := CurrentEditView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and
    TrimLeft(TAtlasEditorBuffer.LineText(mView, mView.CursorPos.Line)).StartsWith('///');
end;

class function TAtlasCodeInsightQueries.InDebugDisplayLine: Boolean;
var
  mView: IOTAEditView;
  mLine, mTemplate: string;
  mColumn: Integer;
  mNames: TArray<string>;
begin
  mView := CurrentEditView;
  Result := False;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mLine := TAtlasEditorBuffer.LineText(mView, mView.CursorPos.Line);
  Result := TDebugDisplayText.CommentTemplate(mLine, mTemplate, mColumn) or
    TDebugDisplayText.AttributeTemplate(mLine, mTemplate, mColumn) or TDebugDisplayText.CommentChildren(mLine, mNames)
    or TDebugDisplayText.AttributeChildren(mLine, mNames);
end;

class function TAtlasCodeInsightQueries.InDataNameString(ATypedQuote: Boolean): Boolean;
var
  mView: IOTAEditView;
  mLine: string;
  mCharacter: Integer;
begin
  Result := False;
  mView := CurrentEditView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mLine := TAtlasEditorBuffer.LineText(mView, mView.CursorPos.Line);
  mCharacter := TLspSession.ColumnToIndex(mLine, mView.CursorPos.Col, TAtlasEditorBuffer.TabWidth(mView.Buffer));
  Result := TAtlasWord.InDataNameString(mLine, mCharacter);
  if not Result and ATypedQuote then
  begin
    Insert('''', mLine, mCharacter + 1);
    Result := TAtlasWord.InDataNameString(mLine, mCharacter + 1);
  end;
end;

/// <summary>Auslöser, die nicht vom Text um den Cursor abhängen: #0 Vervollständigung (Strg+Leer), "." nach dem
/// Punkt, #1 Parameterhilfe (Strg+Umschalt+Leer), "(" und ",", "&lt;" und "[", #2 Browse (Strg+Klick), #3
/// Symbolhinweis. Mit Zeitgeber: nach der in den Editoroptionen eingestellten Verzögerung.</summary>
function FixedType(AChar: Char; out AInvoke: TOTAInvokeType): TOTACodeInsightType;
begin
  AInvoke := itManual;
  case AChar of
    #0, '.', '<', '[':
      Result := citCodeInsight;
    #1, '(', ',':
      Result := citParameterCodeInsight;
    #2:
      Result := citBrowseCodeInsight;
    #3:
      Result := citHintCodeInsight;
  else
    Result := citNone;
  end;
  if CharInSet(AChar, ['.', '<', '[', '(', ',']) then
  begin
    AInvoke := itTimer;
  end;
end;

/// <summary>Auslöser, die vom Text um den Cursor abhängen: ";" hinter einem übernommenen Konstruktor (#489), "{" in
/// einer Wertdarstellung (#854), ' in FieldByName( (#461). Immer mit Zeitgeber.</summary>
function ContextType(AChar: Char; const AGuardPending: TFunc<Boolean>): Boolean;
begin
  case AChar of
    ';':
      Result := AGuardPending();
    '{':
      Result := TAtlasCodeInsightQueries.InDebugDisplayLine;
    '''':
      Result := TAtlasCodeInsightQueries.InDataNameString(True);
  else
    Result := False;
  end;
end;

/// <summary>Vervollständigung in Kommentar oder String, die trotzdem gilt: XMLDoc-Tags in ///-Zeilen (#435), Feld-
/// und Parameternamen im String (#461), Platzhalter in Wertdarstellungen (#854); die Einträge kommen vom Server.
/// </summary>
function KeptInside(AChar: Char; AElement: Integer): Boolean;
begin
  if ((AChar = '<') or (AElement = atComment)) and TAtlasCodeInsightQueries.InXmlDocLine then
  begin
    Exit(True);
  end;
  if (AElement = atString) and TAtlasCodeInsightQueries.InDataNameString(AChar = '''') then
  begin
    Exit(True);
  end;
  Result := ((AElement = atComment) or (AElement = atString)) and TAtlasCodeInsightQueries.InDebugDisplayLine;
end;

class function TAtlasCodeInsightQueries.InsightType(AChar: Char; AElement: Integer;
  const AGuardPending: TFunc<Boolean>; out AInvoke: TOTAInvokeType): TOTACodeInsightType;
begin
  Result := FixedType(AChar, AInvoke);
  if CharInSet(AChar, [';', '{', '''']) and ContextType(AChar, AGuardPending) then
  begin
    Result := citCodeInsight;
    AInvoke := itTimer;
  end;
  // In Kommentaren und Strings keine Vervollständigung (#435), außer KeptInside; "<" außerhalb davon ist ein
  // Vergleich, keine Auslösung.
  if (Result = citCodeInsight) and KeptInside(AChar, AElement) then
  begin
    Exit;
  end;
  if (AChar = '<') or ((Result in [citCodeInsight, citParameterCodeInsight]) and
    ((AElement = atComment) or (AElement = atString))) then
  begin
    Result := citNone;
  end;
end;

/// <summary>Wert im angehaltenen Debugger (#891) vor dem Hover-Text; nur sofort verfügbare Werte, die IDE wartet
/// nicht.</summary>
function WithDebugValue(const AHover, ALine, AFileName: string; ACharacter, AHintLine: Integer): string;
var
  mDebugText: string;
begin
  Result := AHover;
  if not TAtlasIdeSettings.Current.DebugHoverValues or not TAtlasIdeDebugValues.Stopped then
  begin
    Exit;
  end;
  mDebugText := TAtlasIdeDebugValues.EvaluateNow(TAtlasDebugExpression.AtCharacter(ALine, ACharacter), AFileName,
    AHintLine).PlainText;
  if (mDebugText <> '') and (Result <> '') then
  begin
    Result := mDebugText + #13#10#13#10 + Result;
  end
  else if mDebugText <> '' then
  begin
    Result := mDebugText;
  end;
end;

class function TAtlasCodeInsightQueries.HintAt(ASession: TLspSession; const AView: IOTAEditView; AHintLine,
  AHintCol: Integer; const ADiagnose: TProc<string>): string;
var
  mText: string;
  mLines: TArray<string>;
  mCharacter: Integer;
begin
  Result := '';
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  if (AHintLine < 1) or (AHintLine > Length(mLines)) then
  begin
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(mLines[AHintLine - 1], AHintCol, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  // Die IDE wartet im Hauptthread auf den Hinweis: kurzes Zeitlimit.
  Result := ASession.Hover(AView.Buffer.FileName, mText, AHintLine - 1, mCharacter, TLspSession.cMainThreadTimeoutMs);
  Result := WithDebugValue(Result, mLines[AHintLine - 1], AView.Buffer.FileName, mCharacter, AHintLine);
  ADiagnose(Format('Hover (%s), Zeile %d, Spalte %d (Cursor %d/%d): %d Zeichen',
    [ExtractFileExt(AView.Buffer.FileName), AHintLine, AHintCol, AView.CursorPos.Line, AView.CursorPos.Col,
    Length(Result)]));
end;

class function TAtlasCodeInsightQueries.DefinitionOf(ASession: TLspSession; const AView: IOTAEditView; ALine,
  ACharacter: Integer; out ALocation: TLspLocation): Boolean;
begin
  // Ersatz-Units des Servers (atlas-ide:…) gibt es nicht als Datei: kein Sprungziel für Strg+Klick.
  Result := ASession.Definition(AView.Buffer.FileName, TAtlasEditorBuffer.Text(AView.Buffer), ALine, ACharacter,
    ALocation) and not TAtlasIdeMembers.IsIdePath(ALocation.FileName);
end;

class procedure TAtlasCodeInsightQueries.DefinitionAt(ASession: TLspSession; const AView: IOTAEditView;
  AIndex: Integer; const ADiagnose: TProc<string>; out AFileName: string; out ALineNum: Integer);
var
  mText: string;
  mLines: TArray<string>;
  mCursor: TOTAEditPos;
  mCharacter: Integer;
  mLocation: TLspLocation;
begin
  AFileName := '';
  ALineNum := 0;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  // Die synchrone Schnittstelle übergibt keine Klickposition; maßgeblich ist der Cursor.
  mCursor := AView.CursorPos;
  if (mCursor.Line < 1) or (mCursor.Line > Length(mLines)) then
  begin
    ADiagnose(Format('Gehe zu Definition: Cursorzeile %d außerhalb des Puffers (%d Zeilen)',
      [mCursor.Line, Length(mLines)]));
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(mLines[mCursor.Line - 1], mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  if DefinitionOf(ASession, AView, mCursor.Line - 1, mCharacter, mLocation) then
  begin
    AFileName := mLocation.FileName;
    ALineNum := mLocation.Line + 1;
  end;
  ADiagnose(Format('Gehe zu Definition (Index %d) (%s), Zeile %d, Spalte %d (Zeichen %d): %s',
    [AIndex, ExtractFileExt(AView.Buffer.FileName), mCursor.Line, mCursor.Col, mCharacter,
    IfThen(AFileName <> '', Format('%s, Zeile %d', [ExtractFileExt(AFileName), ALineNum]), 'keine Definition')]));
end;

end.
