unit Atlas.Common.Diagnostics.Anonymity.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Wächter für #1478: Markernamen (Projekt, Unit, Pfad, Quelltext, Benutzer) kommen über keine Quelle des
  /// Servers anonym heraus: Logger mit Anonymisierer (--log), Protokoll der Sitzung, Status, Fehlerbericht, Paket.
  /// </summary>
  [TestFixture]
  TAnonymityTests = class
  public
    [Test]
    procedure MarkedValuesBecomeLabels;
    [Test]
    procedure LoggerPipelineHidesMarkerNames;
    [Test]
    procedure RecentLinesKeepMarksForTheSink;
    [Test]
    procedure StatusMappedHidesWorkspace;
    [Test]
    procedure BugReportHidesMarkerNames;
    [Test]
    procedure BugReportNotesClearNames;
    [Test]
    procedure NumericIndexLineStaysReadable;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.RegularExpressions,
  Atlas.Text.LogMarks,
  Atlas.Text.Anonymize,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.TransformSink,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Logging.EntryText;

const
  cRoot = 'C:\MarkerRoot\Kunde';
  cMarkerProject = 'MarkerProjektKunde';
  cMarkerUnit = 'MarkerUnitLager';
  cMarkerCode = 'procedure TMarkerForm.Geheim;';
  cMarkerUser = 'MarkerBenutzer';
  cMarkers: array[0..4] of string = ('MarkerRoot', cMarkerProject, cMarkerUnit, 'TMarkerForm', cMarkerUser);
  // Zahlenzeile des Diagnose-Logs (#1478): bleibt anonym unverändert und lesbar.
  cIndexLinePattern = '^\S+ index project#\d+ \w+ [\d a-z]+ mem \d+ MB$';

type
  TMemorySink = class(TInterfacedObject, ILogSink)
  private
    FLines: TStrings;
  public
    constructor Create(ALines: TStrings);
    procedure Write(const AEntry: TLogEntry);
  end;

constructor TMemorySink.Create(ALines: TStrings);
begin
  inherited Create;
  FLines := ALines;
end;

procedure TMemorySink.Write(const AEntry: TLogEntry);
begin
  FLines.Add(TLogEntryText.Plain(AEntry));
end;

/// <summary>Zeile, wie sie an einer Aufrufstelle des Servers entsteht: Namen, Pfade und Meldung gekennzeichnet.
/// </summary>
function MarkedLine: string;
begin
  Result := Format('Index von %s: Unit %s in %s, Fehler %s, angemeldet als %s',
    [TLogMarks.Name(cMarkerProject), TLogMarks.Name(cMarkerUnit), TLogMarks.Path(cRoot + '\Src\' + cMarkerUnit +
    '.pas'), TLogMarks.Text(cMarkerCode), cMarkerUser]);
end;

procedure AssertNoMarkers(const AText, AWhere: string);
var
  mMarker: string;
begin
  for mMarker in cMarkers do
  begin
    Assert.IsFalse(AText.Contains(mMarker), AWhere + ': ' + mMarker + ' in ' + AText);
  end;
  Assert.IsFalse(AText.Contains('Geheim'), AWhere + ': Quelltext in ' + AText);
  Assert.IsFalse(TLogMarks.HasMarks(AText), AWhere + ': Kennzeichen übrig');
end;

function NewAnonymizer: ILogAnonymizer;
begin
  Result := TLogAnonymizer.Create([cMarkerUser]);
end;

/// <summary>Anonymisierer als Umwandlung der Senke; eigene Routine, damit die Methodenreferenz nichts festhält.
/// </summary>
function TransformOf(const AAnonymizer: ILogAnonymizer): TLogTextTransform;
begin
  Result :=
    function(const AText: string): string
    begin
      Result := AAnonymizer.Anonymize(AText);
    end;
end;

/// <summary>Ersatz im Status über den Anonymisierer, wie Shell.Composition.Status.</summary>
function MapOf(const AAnonymizer: ILogAnonymizer): TLogMarkMap;
begin
  Result :=
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      Result := AAnonymizer.Anonymize(TLogMarks.Mark(AKind, AValue));
    end;
end;

procedure TAnonymityTests.MarkedValuesBecomeLabels;
var
  mAnonymizer: ILogAnonymizer;
begin
  mAnonymizer := NewAnonymizer;
  Assert.AreEqual('Projekt name#1, Datei datei#1.pas, Fehler wert#1, nach 12 ms',
    mAnonymizer.Anonymize('Projekt ' + TLogMarks.Name(cMarkerProject) + ', Datei ' +
    TLogMarks.Path(cRoot + '\' + cMarkerUnit + '.pas') + ', Fehler ' + TLogMarks.Text(cMarkerCode) + ', nach ' +
    TLogMarks.Text('12') + ' ms'));
  // Ein gekennzeichneter Name gilt danach auch ungekennzeichnet als bekannt.
  Assert.AreEqual('Wieder name#1', mAnonymizer.Anonymize('Wieder ' + cMarkerProject));
end;

procedure TAnonymityTests.LoggerPipelineHidesMarkerNames;
var
  mLines: TStringList;
  mLogger: TLogger;
  mLoggerRef: ILogger;
  mPlain: TStringList;
begin
  mLines := TStringList.Create;
  mPlain := TStringList.Create;
  try
    mLogger := TLogger.Create;
    mLoggerRef := mLogger;
    mLogger.AddSink(TTransformLogSink.Create(TMemorySink.Create(mLines), TransformOf(NewAnonymizer)),
      TLogLevel.Debug);
    // Ausgabefenster: Klartext, ohne Kennzeichen.
    mLogger.AddSink(TMemorySink.Create(mPlain), TLogLevel.Debug);
    mLoggerRef.Error(MarkedLine);
    mLoggerRef := nil;
    Assert.AreEqual(1, mLines.Count);
    AssertNoMarkers(mLines.Text, '--log');
    Assert.IsTrue(mPlain.Text.Contains(cMarkerProject), 'Ausgabefenster im Klartext');
    Assert.IsFalse(TLogMarks.HasMarks(mPlain.Text), 'Ausgabefenster ohne Kennzeichen');
  finally
    mPlain.Free;
    mLines.Free;
  end;
end;

procedure TAnonymityTests.RecentLinesKeepMarksForTheSink;
var
  mRecent: TRecentLogSink;
  mSink: ILogSink;
  mLines: TArray<string>;
  mAnonymizer: ILogAnonymizer;
begin
  // Protokoll der Sitzung (Fehlerbericht, Paket): Kennzeichen bleiben, damit anonym ersetzt werden kann.
  mRecent := TRecentLogSink.Create(10);
  mSink := mRecent;
  mSink.Write(TLogEntry.Create(Now, TLogLevel.Info, MarkedLine));
  mLines := mRecent.Lines;
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.IsTrue(TLogMarks.HasMarks(mLines[0]));
  mAnonymizer := NewAnonymizer;
  AssertNoMarkers(mAnonymizer.Anonymize(mLines[0]), 'Protokoll der Sitzung');
  AssertNoMarkers(TTextAnonymizer.AnonymizeLogLine(mLines[0], [cRoot], [cMarkerUser]), 'ohne Anonymisierer');
end;

procedure TAnonymityTests.StatusMappedHidesWorkspace;
var
  mStatus: TServerStatus;
  mWorkspace: TWorkspaceStatus;
  mMap: TLogMarkMap;
begin
  mStatus := Default(TServerStatus);
  mWorkspace := Default(TWorkspaceStatus);
  mWorkspace.Name := cMarkerProject;
  mWorkspace.Project := cRoot + '\' + cMarkerProject + '.dproj';
  mWorkspace.CacheFile := 'C:\Users\' + cMarkerUser + '\AppData\Local\Atlas\' + cMarkerUnit + '.idx';
  mWorkspace.Config := 'Debug';
  mWorkspace.Platform := 'Win64';
  mWorkspace.LastIndexMs := 12;
  mStatus.Workspaces := [mWorkspace];
  mMap := MapOf(NewAnonymizer);
  AssertNoMarkers(mStatus.Mapped(mMap).ToMarkdown, 'Status');
  Assert.IsTrue(mStatus.Mapped(mMap).ToMarkdown.Contains('Win64'), 'Plattform bleibt lesbar');
  mMap := nil;
end;

function MarkerInput(AAnonymize: Boolean): TBugReportInput;
begin
  Result := Default(TBugReportInput);
  Result.ServerVersion := '2.0.0';
  Result.Configuration := '{"project": "' + StringReplace(cRoot, '\', '\\', [rfReplaceAll]) + '\\' +
    cMarkerProject + '.dproj", "profile": "' + cMarkerUnit + '", "delphiVersion": "37.0", "config": "Debug"}';
  Result.LogLines := [MarkedLine];
  Result.Workspaces := [cRoot];
  Result.Identity := [cMarkerUser];
  Result.Anonymize := AAnonymize;
  Result.Created := EncodeDate(2026, 11, 5);
end;

procedure TAnonymityTests.BugReportHidesMarkerNames;
var
  mInput: TBugReportInput;
  mText: string;
begin
  mInput := MarkerInput(True);
  // Wie der Server: das Protokoll der Sitzung über den Anonymisierer, Kennzeichen bleiben bis dorthin.
  mInput.LogLines := [NewAnonymizer.Anonymize(mInput.LogLines[0])];
  mText := TBugReport.Build(mInput);
  AssertNoMarkers(mText, 'Fehlerbericht');
  Assert.IsTrue(mText.Contains('"Debug"'), 'feste Werte bleiben');
  Assert.IsTrue(mText.Contains('"37.0"'), 'Versionen bleiben');
end;

procedure TAnonymityTests.BugReportNotesClearNames;
var
  mText: string;
begin
  // Klarnamen nur nach ausdrücklicher Wahl, sichtbar vermerkt; die Kennzeichen fallen weg.
  mText := TBugReport.Build(MarkerInput(False));
  Assert.IsTrue(mText.Contains('mit Klarnamen (ausdrücklich gewählt)'), mText);
  Assert.IsTrue(mText.Contains(cMarkerProject), mText);
  Assert.IsFalse(TLogMarks.HasMarks(mText));
end;

procedure TAnonymityTests.NumericIndexLineStaysReadable;
const
  cLines: array[0..1] of string = (
    '10:41:31.120 index project#2 cacheWrite library units 3992 18234 kb 812 ms mem 1037 MB',
    '10:41:32.004 index project#1 cacheWrite project units 412 2048 kb 75 ms mem 1040 MB');
var
  mLine: string;
  mAnonymizer: ILogAnonymizer;
begin
  mAnonymizer := NewAnonymizer;
  for mLine in cLines do
  begin
    Assert.AreEqual(mLine, mAnonymizer.Anonymize(mLine), 'Zahlenzeile unverändert');
    Assert.IsTrue(TRegEx.IsMatch(mLine, cIndexLinePattern), mLine);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnonymityTests);

end.
