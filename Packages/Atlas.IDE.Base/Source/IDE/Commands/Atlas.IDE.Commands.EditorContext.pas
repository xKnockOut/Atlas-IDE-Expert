unit Atlas.IDE.Commands.EditorContext;

// Gemeinsamer Stand der Editorbefehle (#399), Vorfahr von TAtlasIdeEditorCommands
// (Atlas.IDE.Commands.Editor, Beschreibung dort): Sitzung und Meldungszeile aus
// Install, die von der Composition gesetzten Rückrufe und die Hilfen für die
// obere Editoransicht (Text an den Server abgleichen, Positionen umrechnen,
// markieren).

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Problems.Contract;

type
  /// <summary>Platzhalter-Modus für eingesetzten Text (#88): ABefore = Puffertext vorher, AOffset = Anfang im
  /// Puffer.</summary>
  TAtlasPlaceholdersProc = reference to procedure(const AView: IOTAEditView; const ABefore: string;
    AOffset: Integer; const AExpansion: TAtlasSnippetExpansion);

  /// <summary>Befunde einer Datei (#509).</summary>
  TAtlasProblemsOfFunc = reference to function(const AFileName: string): TArray<TAtlasProblem>;

  /// <summary>Die obere Editoransicht mit ihren Zeilen und der Schreibmarke als Zeichenindex.</summary>
  TAtlasEditorCaret = record
    View: IOTAEditView;
    Text: string;
    Lines: TArray<string>;
    TabWidth: Integer;
    /// <summary>Zeile der Schreibmarke, 0-basiert.</summary>
    Row: Integer;
    /// <summary>Zeichenindex der Schreibmarke in ihrer Zeile.</summary>
    Character: Integer;
  end;

  /// <summary>Stand und Hilfen der Editorbefehle.</summary>
  TAtlasEditorCommandContext = class
  protected const
    // Code-Aktionen und Befehle des Servers; Befehle können projektweit arbeiten.
    cCommandTimeoutMs = 30000;
  protected class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
    /// <summary>Letzter Auslöser eines Schnellbefehls; gegen wiederholtes Fragen an derselben Stelle.</summary>
    FLastSlash: string;
    /// <summary>Cursor beim ersten Erweitern der Auswahl.</summary>
    FAnchorFile: string;
    FAnchor: TLspTextPosition;
    FProblemsOf: TAtlasProblemsOfFunc;
    FStepList: TFunc<Boolean, Boolean>;
    FOnPlaceholders: TAtlasPlaceholdersProc;
    FOnSignatureHelp: TProc;
    FOnUnitRelations: TProc;
  protected
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
    /// <summary>Oberste Editoransicht, ihr Text (an den Server abgeglichen) und die Auswahl als Bereich
    /// (leer am Cursor ohne Auswahl). False mit Meldung ohne Server oder Editor.</summary>
    class function Current(out AView: IOTAEditView; out AFileName: string; out ALines: TArray<string>;
      out ASelection: TLspRange): Boolean; static;
    /// <summary>Oberste Editoransicht mit Schreibmarke, ohne Server; False ohne Editor.</summary>
    class function Caret(out ACaret: TAtlasEditorCaret): Boolean; static;
    class function EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition;
      ATabWidth: Integer): TOTAEditPos; static;
    class procedure Select(const AView: IOTAEditView; const ALines: TArray<string>; const ARange: TLspRange); static;
    /// <summary>Schreibmarke auf APosition setzen und zeigen.</summary>
    class procedure MoveCaret(const ACaret: TAtlasEditorCaret; const APosition: TLspTextPosition); static;
  public
    /// <summary>Befunde einer Datei für StepProblem; setzt die Composition, nil = keine.</summary>
    class property OnProblemsOf: TAtlasProblemsOfFunc read FProblemsOf write FProblemsOf;
    /// <summary>Bei sichtbarem Fenster „Atlas-Prüfung“ (#909) geht StepProblem durch dessen gefilterte Liste;
    /// True = erledigt. Setzt die Composition, nil = nur die Datei.</summary>
    class property OnStepList: TFunc<Boolean, Boolean> read FStepList write FStepList;
    /// <summary>Platzhalter-Modus für ///-Gerüste (#88); setzt die Composition, nil = nur der Cursor in die
    /// Zusammenfassung.</summary>
    class property OnPlaceholders: TAtlasPlaceholdersProc read FOnPlaceholders write FOnPlaceholders;
    /// <summary>Parameter-Hint an der Schreibmarke öffnen (atlas.showSignatureHelp, #1007); setzt die Composition,
    /// nil = nur der Sprung.</summary>
    class property OnSignatureHelp: TProc read FOnSignatureHelp write FOnSignatureHelp;
    /// <summary>Unit-Beziehungen der Unit im Editor zeigen (atlas.showUnitRelations, #896); setzt die
    /// Composition, nil = nichts.</summary>
    class property OnUnitRelations: TProc read FOnUnitRelations write FOnUnitRelations;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer;

/// <summary>Zeile ARow (1-basiert) von ALines, '' außerhalb.</summary>
function LineAt(const ALines: TArray<string>; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
  begin
    Result := ALines[ARow - 1];
  end;
end;

/// <summary>Zeile und Spalte des Editors (1-basiert) als Position des Servers.</summary>
function LspPosition(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TLspTextPosition;
begin
  Result := TLspTextPosition.Create(ARow - 1, TLspSession.ColumnToIndex(LineAt(ALines, ARow), AColumn, ATabWidth));
end;

/// <summary>Obere Editoransicht mit Puffer oder nil.</summary>
function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
  if (Result <> nil) and (Result.Buffer = nil) then
  begin
    Result := nil;
  end;
end;

class function TAtlasEditorCommandContext.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class procedure TAtlasEditorCommandContext.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasEditorCommandContext.Current(out AView: IOTAEditView; out AFileName: string;
  out ALines: TArray<string>; out ASelection: TLspRange): Boolean;
var
  mRunning: TLspSession;
  mText: string;
  mBlock: IOTAEditBlock;
  mCursor: TOTAEditPos;
  mTabWidth: Integer;
begin
  Result := False;
  AFileName := '';
  ALines := nil;
  ASelection := Default(TLspRange);
  AView := nil;
  mRunning := Session;
  if mRunning = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  AView := TopView;
  if AView = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  AFileName := AView.Buffer.FileName;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mRunning.Sync(AFileName, mText);
  ALines := mText.Split([#13#10, #10]);
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mCursor := AView.CursorPos;
  ASelection.StartPos := LspPosition(ALines, mCursor.Line, mCursor.Col, mTabWidth);
  ASelection.EndPos := ASelection.StartPos;
  mBlock := AView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) then
  begin
    ASelection.StartPos := LspPosition(ALines, mBlock.StartingRow, mBlock.StartingColumn, mTabWidth);
    ASelection.EndPos := LspPosition(ALines, mBlock.EndingRow, mBlock.EndingColumn, mTabWidth);
  end;
  Result := True;
end;

class function TAtlasEditorCommandContext.Caret(out ACaret: TAtlasEditorCaret): Boolean;
var
  mCursor: TOTAEditPos;
begin
  ACaret := Default(TAtlasEditorCaret);
  ACaret.View := TopView;
  Result := ACaret.View <> nil;
  if not Result then
  begin
    Exit;
  end;
  ACaret.Text := TAtlasEditorBuffer.Text(ACaret.View.Buffer);
  ACaret.Lines := ACaret.Text.Split([#13#10, #10]);
  ACaret.TabWidth := TAtlasEditorBuffer.TabWidth(ACaret.View.Buffer);
  mCursor := ACaret.View.CursorPos;
  ACaret.Row := mCursor.Line - 1;
  ACaret.Character := TLspSession.ColumnToIndex(LineAt(ACaret.Lines, mCursor.Line), mCursor.Col, ACaret.TabWidth);
end;

class function TAtlasEditorCommandContext.EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition;
  ATabWidth: Integer): TOTAEditPos;
begin
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineAt(ALines, APosition.Line + 1), APosition.Character, ATabWidth);
end;

class procedure TAtlasEditorCommandContext.Select(const AView: IOTAEditView; const ALines: TArray<string>;
  const ARange: TLspRange);
var
  mTabWidth: Integer;
begin
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  AView.Block.Style := btNonInclusive;
  AView.CursorPos := EditPos(ALines, ARange.StartPos, mTabWidth);
  // Anfang markieren, Cursor ans Ende, Ende markieren: Der Cursor steht danach am Ende der Auswahl.
  AView.Block.BeginBlock;
  AView.CursorPos := EditPos(ALines, ARange.EndPos, mTabWidth);
  AView.Block.EndBlock;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class procedure TAtlasEditorCommandContext.MoveCaret(const ACaret: TAtlasEditorCaret;
  const APosition: TLspTextPosition);
begin
  ACaret.View.CursorPos := EditPos(ACaret.Lines, APosition, ACaret.TabWidth);
  ACaret.View.MoveViewToCursor;
  ACaret.View.Paint;
end;

end.
