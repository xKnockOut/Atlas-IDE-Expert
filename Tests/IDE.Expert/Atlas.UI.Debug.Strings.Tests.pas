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
  Atlas.UI.Strings,
  Atlas.UI.Strings.Tests,
  Atlas.UI.Debug.AccessViolation.Strings,
  Atlas.UI.Debug.Breakpoints.Strings,
  Atlas.UI.Debug.CallStack.Strings,
  Atlas.UI.Debug.Commands.Strings,
  Atlas.UI.Debug.DataBreakpoints.Strings,
  Atlas.UI.Debug.Evaluate.Strings,
  Atlas.UI.Debug.EventBreak.Strings,
  Atlas.UI.Debug.EventLog.Strings,
  Atlas.UI.Debug.Exceptions.Strings,
  Atlas.UI.Debug.Explain.Strings,
  Atlas.UI.Debug.Logpoints.Strings,
  Atlas.UI.Debug.MethodBreakpoints.Strings,
  Atlas.UI.Debug.RuntimeReport.Strings,
  Atlas.UI.Debug.Session.Strings,
  Atlas.UI.Debug.Settings.Strings,
  Atlas.UI.Debug.Stepping.Strings,
  Atlas.UI.Debug.Threads.Strings,
  Atlas.UI.Debug.Values.Strings;

type
  /// <summary>Text zur Id mit der Ordnungszahl AIndex in der aktuellen Sprache.</summary>
  TTableText = reference to function(AIndex: Integer): string;

  TTable = record
    Name: string;
    Count: Integer;
    Text: TTableText;
  end;

function Table(const AName: string; ACount: Integer; const AText: TTableText): TTable;
begin
  Result.Name := AName;
  Result.Count := ACount;
  Result.Text := AText;
end;

/// <summary>Texttabellen von Einstellungen, Menü, Werten und Auswertung.</summary>
function ValueTables: TArray<TTable>;
begin
  SetLength(Result, 6);
  Result[0] := Table('Settings', Ord(High(TAtlasDebugSettingsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasDebugSettingsStrings.Text(TAtlasDebugSettingsTextId(AIndex));
    end);
  Result[1] := Table('Commands', Ord(High(TAtlasDebugCommandsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId(AIndex));
    end);
  Result[2] := Table('Values', Ord(High(TAtlasValuesTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasValuesStrings.Text(TAtlasValuesTextId(AIndex));
    end);
  Result[3] := Table('Evaluate', Ord(High(TAtlasEvaluateTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasEvaluateStrings.Text(TAtlasEvaluateTextId(AIndex));
    end);
  Result[4] := Table('Explain', Ord(High(TAtlasExplainTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasExplainStrings.Text(TAtlasExplainTextId(AIndex));
    end);
  Result[5] := Table('Breakpoints', Ord(High(TAtlasBreakpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId(AIndex));
    end);
end;

/// <summary>Texttabellen der Haltepunkte und Exceptions.</summary>
function BreakpointTables: TArray<TTable>;
begin
  SetLength(Result, 6);
  Result[0] := Table('DataBreakpoints', Ord(High(TAtlasDataBreakpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasDataBreakpointsStrings.Text(TAtlasDataBreakpointsTextId(AIndex));
    end);
  Result[1] := Table('MethodBreakpoints', Ord(High(TAtlasMethodBreakpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId(AIndex));
    end);
  Result[2] := Table('EventBreak', Ord(High(TAtlasEventBreakTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasEventBreakStrings.Text(TAtlasEventBreakTextId(AIndex));
    end);
  Result[3] := Table('Logpoints', Ord(High(TAtlasLogpointsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId(AIndex));
    end);
  Result[4] := Table('Exceptions', Ord(High(TAtlasExceptionsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId(AIndex));
    end);
  Result[5] := Table('AccessViolation', Ord(High(TAtlasAccessViolationTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasAccessViolationStrings.Text(TAtlasAccessViolationTextId(AIndex));
    end);
end;

/// <summary>Texttabellen von Threads, Schrittbetrieb und Sitzung.</summary>
function RunTables: TArray<TTable>;
begin
  SetLength(Result, 6);
  Result[0] := Table('Threads', Ord(High(TAtlasThreadsTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasThreadsStrings.Text(TAtlasThreadsTextId(AIndex));
    end);
  Result[1] := Table('CallStack', Ord(High(TAtlasCallStackTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasCallStackStrings.Text(TAtlasCallStackTextId(AIndex));
    end);
  Result[2] := Table('Stepping', Ord(High(TAtlasSteppingTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasSteppingStrings.Text(TAtlasSteppingTextId(AIndex));
    end);
  Result[3] := Table('EventLog', Ord(High(TAtlasEventLogTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasEventLogStrings.Text(TAtlasEventLogTextId(AIndex));
    end);
  Result[4] := Table('Session', Ord(High(TAtlasSessionTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasSessionStrings.Text(TAtlasSessionTextId(AIndex));
    end);
  Result[5] := Table('RuntimeReport', Ord(High(TAtlasRuntimeReportTextId)) + 1,
    function(AIndex: Integer): string
    begin
      Result := TAtlasRuntimeReportStrings.Text(TAtlasRuntimeReportTextId(AIndex));
    end);
end;

/// <summary>Die Texttabellen aller Features des Moduls.</summary>
function Tables: TArray<TTable>;
begin
  Result := ValueTables + BreakpointTables + RunTables;
end;

{ TAtlasDebugStringsTests }

procedure TAtlasDebugStringsTests.EveryTextExistsInBothLanguages;
var
  mTable: TTable;
  mIndex: Integer;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mTable in Tables do
    begin
      Assert.IsTrue(mTable.Count > 0, mTable.Name);
      for mIndex := 0 to mTable.Count - 1 do
      begin
        TAtlasStrings.Language := TAtlasLanguage.German;
        mGerman := mTable.Text(mIndex);
        TAtlasStrings.Language := TAtlasLanguage.English;
        AssertTextPair(mGerman, mTable.Text(mIndex), mIndex);
      end;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasDebugStringsTests.FollowsLanguageOfBase;
var
  mTable: TTable;
  mIndex: Integer;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für jede Tabelle des Moduls.
  mSaved := TAtlasStrings.Language;
  try
    for mTable in Tables do
    begin
      mDiffers := 0;
      for mIndex := 0 to mTable.Count - 1 do
      begin
        TAtlasStrings.Language := TAtlasLanguage.German;
        mGerman := mTable.Text(mIndex);
        TAtlasStrings.Language := TAtlasLanguage.English;
        if mGerman <> mTable.Text(mIndex) then
        begin
          Inc(mDiffers);
        end;
      end;
      Assert.IsTrue(mDiffers > 0, mTable.Name + ': kein Text folgt der Sprache von Base');
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugStringsTests);

end.
