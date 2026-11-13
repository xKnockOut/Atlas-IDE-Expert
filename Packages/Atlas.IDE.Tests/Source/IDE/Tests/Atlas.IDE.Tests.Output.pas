unit Atlas.IDE.Tests.Output;

// Ausgabe des Testläufers (#69) in der Meldungsansicht (Gruppe Atlas), aus
// Atlas.IDE.Tests.Runner gelöst:
// - Say schreibt eine Zeile, Failures je Fehlschlag eine anklickbare Zeile,
//   die zur Testmethode springt.
// - Lauf im Hintergrund (#1775, tests.onSave): Zwischen BeginQuiet und
//   EndQuiet schreibt Tell nichts in die Meldungsansicht, damit kein Fenster
//   aufspringt; Zeilen und Fehlschläge bleiben stehen, bis ShowLast sie auf
//   Klick im Statusfeld zeigt. EndQuiet meldet das Ende über OnQuietEnded.
// - Jump schreibt eine anklickbare Zeile zu einer Stelle (ungetestete
//   Methoden des Projekts, #1783), ShowView zeigt die Meldungsansicht.

interface

uses
  System.SysUtils,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run;

type
  /// <summary>Ende eines Laufs im Hintergrund (#1775).</summary>
  TAtlasTestsQuietEnd = record
    /// <summary>Ein gültiger Bericht wurde gelesen; sonst steht der Grund in Text.</summary>
    Reported: Boolean;
    Passed: Integer;
    /// <summary>Fehlgeschlagen einschließlich Fehler.</summary>
    Failed: Integer;
    Total: Integer;
    /// <summary>Letzte Zeile des Laufs (Zusammenfassung bzw. Grund).</summary>
    Text: string;
  end;
  TAtlasTestsQuietEndProc = reference to procedure(const AEnd: TAtlasTestsQuietEnd);

  TAtlasIdeTestsOutput = class
  private
    FQuiet: Boolean;
    FLines: TArray<string>;
    FFailures: TArray<TAtlasTestFailure>;
    FOnQuietEnded: TAtlasTestsQuietEndProc;
  public
    /// <summary>Zeile in der Meldungsansicht, immer.</summary>
    procedure Say(const AText: string);
    /// <summary>Zeile eines Laufs: im Hintergrund gemerkt, sonst wie Say.</summary>
    procedure Tell(const AText: string);
    /// <summary>Fehlschläge eines Laufs: im Hintergrund gemerkt, sonst je eine anklickbare Zeile.</summary>
    procedure Failures(const AFailures: TArray<TAtlasTestFailure>);
    /// <summary>Anklickbare Zeile AText, die zu AFileName an ALine und AColumn (0-basiert) springt.</summary>
    procedure Jump(const AFileName, AText: string; ALine, AColumn: Integer);
    /// <summary>Meldungsansicht mit der Gruppe Atlas zeigen.</summary>
    procedure ShowView;
    /// <summary>Ein Lauf im Hintergrund beginnt; vergisst die Zeilen des vorigen.</summary>
    procedure BeginQuiet;
    /// <summary>Ende eines Laufs; nur im Hintergrund wirksam (OnQuietEnded). ARun zählt nur mit AReported.</summary>
    procedure EndQuiet(AReported: Boolean; const ARun: TTestRunResult);
    /// <summary>Zeilen und Fehlschläge des letzten Laufs im Hintergrund in die Meldungsansicht und diese zeigen;
    /// False ohne solchen Lauf.</summary>
    function ShowLast: Boolean;
    /// <summary>Läuft gerade ein Lauf im Hintergrund?</summary>
    property Quiet: Boolean read FQuiet;
    property OnQuietEnded: TAtlasTestsQuietEndProc read FOnQuietEnded write FOnQuietEnded;
  end;

implementation

uses
  ToolsAPI,
  Atlas.UI.Tests.Strings;

const
  cMessageGroup = 'Atlas';

function Group(const AMessages: IOTAMessageServices): IOTAMessageGroup;
begin
  Result := AMessages.GetGroup(cMessageGroup);
  if Result = nil then
  begin
    Result := AMessages.AddMessageGroup(cMessageGroup);
  end;
end;

function ProblemText(const ACase: TTestCaseResult): string;
begin
  Result := TAtlasTestRun.ProblemText(ACase, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblem),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblemValues));
end;

{ TAtlasIdeTestsOutput }

procedure TAtlasIdeTestsOutput.Say(const AText: string);
var
  mMessages: IOTAMessageServices;
begin
  if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.AddTitleMessage(AText, Group(mMessages));
  end;
end;

procedure TAtlasIdeTestsOutput.Tell(const AText: string);
begin
  if FQuiet then
  begin
    FLines := FLines + [AText];
  end
  else
  begin
    Say(AText);
  end;
end;

procedure TAtlasIdeTestsOutput.Failures(const AFailures: TArray<TAtlasTestFailure>);
var
  mMessages: IOTAMessageServices;
  mFailure: TAtlasTestFailure;
  mLineRef: Pointer;
begin
  if FQuiet then
  begin
    FFailures := AFailures;
    Exit;
  end;
  if (Length(AFailures) = 0) or not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  for mFailure in AFailures do
  begin
    if mFailure.FileName <> '' then
    begin
      mMessages.AddToolMessage(mFailure.FileName, ProblemText(mFailure.Test), 'DUnitX', mFailure.Line + 1,
        mFailure.StartCharacter + 1, nil, mLineRef, Group(mMessages));
    end
    else
    begin
      mMessages.AddTitleMessage('  ' + ProblemText(mFailure.Test), Group(mMessages));
    end;
  end;
end;

procedure TAtlasIdeTestsOutput.Jump(const AFileName, AText: string; ALine, AColumn: Integer);
var
  mMessages: IOTAMessageServices;
  mLineRef: Pointer;
begin
  if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.AddToolMessage(AFileName, AText, cMessageGroup, ALine + 1, AColumn + 1, nil, mLineRef,
      Group(mMessages));
  end;
end;

procedure TAtlasIdeTestsOutput.ShowView;
var
  mMessages: IOTAMessageServices;
begin
  if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.ShowMessageView(Group(mMessages));
  end;
end;

procedure TAtlasIdeTestsOutput.BeginQuiet;
begin
  FQuiet := True;
  FLines := nil;
  FFailures := nil;
end;

procedure TAtlasIdeTestsOutput.EndQuiet(AReported: Boolean; const ARun: TTestRunResult);
var
  mEnd: TAtlasTestsQuietEnd;
begin
  if not FQuiet then
  begin
    Exit;
  end;
  FQuiet := False;
  mEnd := Default(TAtlasTestsQuietEnd);
  mEnd.Reported := AReported;
  if AReported then
  begin
    mEnd.Passed := ARun.Count(TTestOutcome.Passed);
    mEnd.Failed := ARun.Count(TTestOutcome.Failed) + ARun.Count(TTestOutcome.Error);
    mEnd.Total := ARun.Total;
  end;
  if Length(FLines) > 0 then
  begin
    mEnd.Text := FLines[High(FLines)];
  end;
  if Assigned(FOnQuietEnded) then
  begin
    FOnQuietEnded(mEnd);
  end;
end;

function TAtlasIdeTestsOutput.ShowLast: Boolean;
var
  mMessages: IOTAMessageServices;
  mLine: string;
begin
  Result := (Length(FLines) > 0) and not FQuiet and Supports(BorlandIDEServices, IOTAMessageServices, mMessages);
  if not Result then
  begin
    Exit;
  end;
  for mLine in FLines do
  begin
    Say(mLine);
  end;
  // FQuiet ist aus: Failures schreibt die Zeilen, statt sie zu merken.
  Failures(FFailures);
  mMessages.ShowMessageView(Group(mMessages));
end;

end.
