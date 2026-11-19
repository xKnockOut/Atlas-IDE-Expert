unit Atlas.UI.Debug.Strings.Tests;

// Texte des Moduls Debugger (#1455), je Feature eine Tabelle: jede Id in beiden Sprachen, gleiche Platzhalter,
// und jede Tabelle folgt der Sprache von Base.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FollowsLanguageOfBase;
  end;

implementation

uses
  Atlas.UI.Strings.Tests,
  Atlas.UI.Debug.AccessViolation.Strings,
  Atlas.UI.Debug.Breakpoints.Strings,
  Atlas.UI.Debug.CallStack.Strings,
  Atlas.UI.Debug.Commands.Strings,
  Atlas.UI.Debug.DataBreakpoints.Strings,
  Atlas.UI.Debug.Elapsed.Strings,
  Atlas.UI.Debug.Evaluate.Strings,
  Atlas.UI.Debug.EventBreak.Strings,
  Atlas.UI.Debug.EventLog.Strings,
  Atlas.UI.Debug.Exceptions.Strings,
  Atlas.UI.Debug.Explain.Strings,
  Atlas.UI.Debug.Logpoints.Strings,
  Atlas.UI.Debug.MethodBreakpoints.Strings,
  Atlas.UI.Debug.Note.Strings,
  Atlas.UI.Debug.OpenedFiles.Strings,
  Atlas.UI.Debug.RuntimeReport.Strings,
  Atlas.UI.Debug.Session.Strings,
  Atlas.UI.Debug.Settings.Strings,
  Atlas.UI.Debug.Stepping.Strings,
  Atlas.UI.Debug.Threads.Strings,
  Atlas.UI.Debug.Values.Strings;

/// <summary>Texttabellen von Einstellungen, Menü, Werten und Auswertung.</summary>
function ValueTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 6);
  Result[0] := TextTable('Settings', Ord(High(TAtlasDebugSettingsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId(AIndex));
    end);
  Result[1] := TextTable('Commands', Ord(High(TAtlasDebugCommandsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId(AIndex));
    end);
  Result[2] := TextTable('Values', Ord(High(TAtlasValuesTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId(AIndex));
    end);
  Result[3] := TextTable('Evaluate', Ord(High(TAtlasEvaluateTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId(AIndex));
    end);
  Result[4] := TextTable('Explain', Ord(High(TAtlasExplainTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasExplainStrings.Text(TAtlasExplainTextId(AIndex));
    end);
  Result[5] := TextTable('Breakpoints', Ord(High(TAtlasBreakpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId(AIndex));
    end);
end;

/// <summary>Texttabellen der Haltepunkte und Exceptions.</summary>
function BreakpointTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 6);
  Result[0] := TextTable('DataBreakpoints', Ord(High(TAtlasDataBreakpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasDataBreakpointsStrings.Text(TAtlasDataBreakpointsTextId(AIndex));
    end);
  Result[1] := TextTable('MethodBreakpoints', Ord(High(TAtlasMethodBreakpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId(AIndex));
    end);
  Result[2] := TextTable('EventBreak', Ord(High(TAtlasEventBreakTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasEventBreakStrings.Text(TAtlasEventBreakTextId(AIndex));
    end);
  Result[3] := TextTable('Logpoints', Ord(High(TAtlasLogpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId(AIndex));
    end);
  Result[4] := TextTable('Exceptions', Ord(High(TAtlasExceptionsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId(AIndex));
    end);
  Result[5] := TextTable('AccessViolation', Ord(High(TAtlasAccessViolationTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasAccessViolationStrings.Text(TAtlasAccessViolationTextId(AIndex));
    end);
end;

/// <summary>Texttabellen von Threads, Schrittbetrieb und Sitzung.</summary>
function RunTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 6);
  Result[0] := TextTable('Threads', Ord(High(TAtlasThreadsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasThreadsStrings.Text(TAtlasThreadsTextId(AIndex));
    end);
  Result[1] := TextTable('CallStack', Ord(High(TAtlasCallStackTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasCallStackStrings.Text(TAtlasCallStackTextId(AIndex));
    end);
  Result[2] := TextTable('Stepping', Ord(High(TAtlasSteppingTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasSteppingStrings.Text(TAtlasSteppingTextId(AIndex));
    end);
  Result[3] := TextTable('EventLog', Ord(High(TAtlasEventLogTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasEventLogStrings.Text(TAtlasEventLogTextId(AIndex));
    end);
  Result[4] := TextTable('Session', Ord(High(TAtlasSessionTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasSessionStrings.Text(TAtlasSessionTextId(AIndex));
    end);
  Result[5] := TextTable('RuntimeReport', Ord(High(TAtlasRuntimeReportTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasRuntimeReportStrings.Text(TAtlasRuntimeReportTextId(AIndex));
    end);
end;

/// <summary>Texttabellen rund um die Sitzung: Debug-Notiz, vom Debugger geöffnete Dateien.</summary>
function SessionTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 2);
  Result[0] := TextTable('Note', Ord(High(TAtlasNoteTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasNoteStrings.Text(TAtlasNoteTextId(AIndex));
    end);
  Result[1] := TextTable('OpenedFiles', Ord(High(TAtlasOpenedFilesTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId(AIndex));
    end);
end;

/// <summary>Texttabellen der Anzeigen im Editor rund um den Ausführungspunkt.</summary>
function EditorTables: TArray<TAtlasTextTable>;
begin
  SetLength(Result, 1);
  Result[0] := TextTable('Elapsed', Ord(High(TAtlasElapsedTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasElapsedStrings.Text(TAtlasElapsedTextId(AIndex));
    end);
end;

/// <summary>Die Texttabellen aller Features des Moduls.</summary>
function Tables: TArray<TAtlasTextTable>;
begin
  Result := ValueTables + BreakpointTables + RunTables + SessionTables + EditorTables;
end;

{ TAtlasDebugStringsTests }

procedure TAtlasDebugStringsTests.EveryTextExistsInBothLanguages;
begin
  AssertTablesInBothLanguages(Tables);
end;

procedure TAtlasDebugStringsTests.FollowsLanguageOfBase;
begin
  AssertTablesFollowLanguage(Tables);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugStringsTests);

end.
