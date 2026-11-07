unit Atlas.IDE.Tasks.Output;

// Register „Atlas-Aufgaben“ im Fenster Meldungen (#900):
// - Je Lauf eine Kopfzeile (eigene Zeichnung, INTACustomDrawMessage): Name,
//   Exit-Code, Dauer, Zahl der Befunde; grün bei Exit-Code 0, sonst rot,
//   solange der Lauf läuft in der Farbe des Fensters.
// - Darunter die Ausgabe zeilenweise, sobald sie kommt (Lines); erkannte
//   Fundstellen als Werkzeugmeldung mit Datei, Zeile und Spalte, ein
//   Doppelklick springt hin.
// - „nur Befunde“ (tasks.onlyFindings) zeigt je Lauf nur Kopfzeile und
//   Fundstellen. Umschalten und das Ende eines Laufs bauen das Register aus
//   den gemerkten Läufen neu auf (die Kopfzeile steht über ihrer Ausgabe).
// - Gemerkt werden die letzten MaxRuns Läufe der Sitzung mit höchstens
//   MaxLines Zeilen; der Rest erscheint als „… n weitere Zeilen“.
// - Clear entfernt nur eine Gruppe, die Atlas angelegt hat, und beim Beenden
//   der IDE gar nichts (TAtlasTaskOutputGroup): Dann hat die IDE das
//   Meldungsfenster samt Gruppen schon abgebaut.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.OutputGroup,
  Atlas.Core.Tasks.Runs;

type
  TAtlasIdeTaskOutput = class
  public const
    cMaxRuns = 20;
    cMaxLines = 5000;
  private type
    TEntry = class
      FId: Integer;
      FName: string;
      FCommandLine: string;
      FTimeoutSec: Integer;
      FRunning: Boolean;
      FRun: TAtlasTaskRun;
      FLines: TArray<string>;
      /// <summary>Je Zeile der Index in Findings, -1 ohne.</summary>
      FLineFinding: TArray<Integer>;
      FFindings: TAtlasTaskFindings;
      FDropped: Integer;
    end;
  private
    FEntries: TObjectList<TEntry>;
    FOnlyFindings: Boolean;
    FGroup: TAtlasTaskOutputGroup;
    /// <summary>Gruppe „Atlas-Aufgaben“; mit ACreate angelegt, falls sie fehlt.</summary>
    function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
    function Find(AId: Integer): TEntry;
    procedure SetOnlyFindings(AValue: Boolean);
    procedure AddHeader(AEntry: TEntry);
    procedure AddLine(AEntry: TEntry; AIndex: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ein Lauf beginnt: Kopfzeile „läuft“ anhängen, Register zeigen.</summary>
    procedure Started(AId: Integer; const AName, ACommandLine: string; ATimeoutSec: Integer; AShow: Boolean);
    /// <summary>Neue Zeilen des Laufs; AFindings mit OutputLine als Index in die ganze Ausgabe.</summary>
    procedure Lines(AId: Integer; const ALines: TArray<string>; const AFindings: TAtlasTaskFindings);
    /// <summary>Ende des Laufs mit Ergebnis; baut das Register neu auf.</summary>
    procedure Finished(AId: Integer; const ARun: TAtlasTaskRun);
    /// <summary>Register aus den gemerkten Läufen neu aufbauen.</summary>
    procedure Render;
    /// <summary>Register entfernen und Läufe vergessen.</summary>
    procedure Clear;
    property OnlyFindings: Boolean read FOnlyFindings write SetOnlyFindings;
  end;

implementation

uses
  System.Types,
  System.Classes,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.UI.Build.Strings,
  Atlas.UI.Tasks.Texts;

type
  /// <summary>Kopfzeile mit eigener Farbe; Text und Farbe stehen beim Hinzufügen fest.</summary>
  THeaderMessage = class(TInterfacedObject, IOTACustomMessage, INTACustomDrawMessage)
  private
    FText: string;
    FColor: TColor;
  public
    constructor Create(const AText: string; AColor: TColor);
    { IOTACustomMessage }
    function GetColumnNumber: Integer;
    function GetFileName: string;
    function GetLineNumber: Integer;
    function GetLineText: string;
    procedure ShowHelp;
    { INTACustomDrawMessage }
    procedure Draw(Canvas: TCanvas; const Rect: TRect; Wrap: Boolean);
    function CalcRect(Canvas: TCanvas; MaxWidth: Integer; Wrap: Boolean): TRect;
  end;

/// <summary>Die IDE wird beendet: Sie hat das Meldungsfenster schon abgebaut, bevor sie Atlas entlädt.</summary>
function IdeClosing: Boolean;
begin
  Result := Application.Terminated or (Application.MainForm = nil) or
    (csDestroying in Application.MainForm.ComponentState);
end;

{ THeaderMessage }

constructor THeaderMessage.Create(const AText: string; AColor: TColor);
begin
  inherited Create;
  FText := AText;
  FColor := AColor;
end;

function THeaderMessage.GetColumnNumber: Integer;
begin
  Result := 0;
end;

function THeaderMessage.GetFileName: string;
begin
  Result := '';
end;

function THeaderMessage.GetLineNumber: Integer;
begin
  Result := 0;
end;

function THeaderMessage.GetLineText: string;
begin
  Result := FText;
end;

procedure THeaderMessage.ShowHelp;
begin
end;

procedure THeaderMessage.Draw(Canvas: TCanvas; const Rect: TRect; Wrap: Boolean);
var
  mArea: TRect;
begin
  mArea := Rect;
  Canvas.Font.Style := [fsBold];
  if FColor <> clNone then
  begin
    Canvas.Font.Color := FColor;
  end;
  Canvas.TextRect(mArea, mArea.Left + 2, mArea.Top, FText);
end;

function THeaderMessage.CalcRect(Canvas: TCanvas; MaxWidth: Integer; Wrap: Boolean): TRect;
begin
  Canvas.Font.Style := [fsBold];
  Result := System.Types.Rect(0, 0, Canvas.TextWidth(FText) + 4, Canvas.TextHeight(FText) + 2);
end;

{ TAtlasIdeTaskOutput }

function TAtlasIdeTaskOutput.Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  mName: string;
begin
  mName := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGroup);
  Result := AMessages.GetGroup(mName);
  if (Result = nil) and ACreate then
  begin
    Result := AMessages.AddMessageGroup(mName);
  end;
  if Result <> nil then
  begin
    FGroup.Used;
  end;
end;

constructor TAtlasIdeTaskOutput.Create;
begin
  inherited Create;
  FEntries := TObjectList<TEntry>.Create(True);
end;

destructor TAtlasIdeTaskOutput.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

function TAtlasIdeTaskOutput.Find(AId: Integer): TEntry;
var
  mEntry: TEntry;
begin
  for mEntry in FEntries do
  begin
    if mEntry.FId = AId then
    begin
      Exit(mEntry);
    end;
  end;
  Result := nil;
end;

procedure TAtlasIdeTaskOutput.SetOnlyFindings(AValue: Boolean);
begin
  if FOnlyFindings = AValue then
  begin
    Exit;
  end;
  FOnlyFindings := AValue;
  Render;
end;

procedure TAtlasIdeTaskOutput.AddHeader(AEntry: TEntry);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
  mColors: TAtlasColors;
  mColor: TColor;
  mText: string;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, True);
  if mTarget = nil then
  begin
    Exit;
  end;
  if AEntry.FRunning then
  begin
    mText := TAtlasTaskTexts.Running(AEntry.FName, AEntry.FCommandLine);
    mColor := clNone;
  end
  else
  begin
    mText := TAtlasTaskTexts.Header(AEntry.FRun, AEntry.FTimeoutSec);
    mColors := TAtlasIdeStyle.Colors;
    if AEntry.FRun.ExitedCleanly then
    begin
      mColor := TColor(mColors.Add);
    end
    else
    begin
      mColor := TColor(mColors.Error);
    end;
  end;
  mMessages.AddCustomMessage(THeaderMessage.Create(mText, mColor) as IOTACustomMessage, mTarget);
end;

procedure TAtlasIdeTaskOutput.AddLine(AEntry: TEntry; AIndex: Integer);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
  mFinding: TAtlasTaskFinding;
  mLineRef: Pointer;
  mLine: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, True);
  if mTarget = nil then
  begin
    Exit;
  end;
  if (AIndex <= High(AEntry.FLineFinding)) and (AEntry.FLineFinding[AIndex] >= 0) then
  begin
    mFinding := AEntry.FFindings[AEntry.FLineFinding[AIndex]];
    if mFinding.FileName <> '' then
    begin
      mLine := mFinding.Line;
      if mLine < 1 then
      begin
        mLine := 1;
      end;
      mMessages.AddToolMessage(mFinding.FileName, AEntry.FLines[AIndex], AEntry.FName, mLine, mFinding.Column, nil,
        mLineRef, mTarget);
      Exit;
    end;
  end
  else if FOnlyFindings then
  begin
    Exit;
  end;
  mMessages.AddTitleMessage('  ' + AEntry.FLines[AIndex], mTarget);
end;

procedure TAtlasIdeTaskOutput.Started(AId: Integer; const AName, ACommandLine: string; ATimeoutSec: Integer;
  AShow: Boolean);
var
  mEntry: TEntry;
  mMessages: IOTAMessageServices;
begin
  mEntry := TEntry.Create;
  mEntry.FId := AId;
  mEntry.FName := AName;
  mEntry.FCommandLine := ACommandLine;
  mEntry.FTimeoutSec := ATimeoutSec;
  mEntry.FRunning := True;
  FEntries.Add(mEntry);
  while FEntries.Count > cMaxRuns do
  begin
    FEntries.Delete(0);
  end;
  AddHeader(mEntry);
  if AShow and Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.ShowMessageView(Group(mMessages, True));
  end;
end;

procedure TAtlasIdeTaskOutput.Lines(AId: Integer; const ALines: TArray<string>; const AFindings: TAtlasTaskFindings);
var
  mEntry: TEntry;
  mFinding: TAtlasTaskFinding;
  mLine: string;
  mFirst, mIndex: Integer;
begin
  mEntry := Find(AId);
  if mEntry = nil then
  begin
    Exit;
  end;
  mFirst := Length(mEntry.FLines);
  for mLine in ALines do
  begin
    if Length(mEntry.FLines) < cMaxLines then
    begin
      mEntry.FLines := mEntry.FLines + [mLine];
      mEntry.FLineFinding := mEntry.FLineFinding + [-1];
    end
    else
    begin
      Inc(mEntry.FDropped);
    end;
  end;
  for mFinding in AFindings do
  begin
    mEntry.FFindings := mEntry.FFindings + [mFinding];
    if (mFinding.OutputLine >= 0) and (mFinding.OutputLine <= High(mEntry.FLineFinding)) then
    begin
      mEntry.FLineFinding[mFinding.OutputLine] := High(mEntry.FFindings);
    end;
  end;
  for mIndex := mFirst to High(mEntry.FLines) do
  begin
    AddLine(mEntry, mIndex);
  end;
end;

procedure TAtlasIdeTaskOutput.Finished(AId: Integer; const ARun: TAtlasTaskRun);
var
  mEntry: TEntry;
begin
  mEntry := Find(AId);
  if mEntry = nil then
  begin
    Exit;
  end;
  mEntry.FRunning := False;
  mEntry.FRun := ARun;
  Render;
end;

procedure TAtlasIdeTaskOutput.Render;
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
  mEntry: TEntry;
  mIndex: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, FEntries.Count > 0);
  if mTarget = nil then
  begin
    Exit;
  end;
  mMessages.ClearMessageGroup(mTarget);
  for mEntry in FEntries do
  begin
    AddHeader(mEntry);
    for mIndex := 0 to High(mEntry.FLines) do
    begin
      AddLine(mEntry, mIndex);
    end;
    if (mEntry.FDropped > 0) and not FOnlyFindings then
    begin
      mMessages.AddTitleMessage(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksMoreLines, [mEntry.FDropped]), mTarget);
    end;
  end;
end;

procedure TAtlasIdeTaskOutput.Clear;
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
begin
  FEntries.Clear;
  // Ohne eigene Gruppe und beim Beenden der IDE das Meldungsfenster nicht anfassen.
  if FGroup.Release(IdeClosing) <> TAtlasTaskOutputRelease.Remove then
  begin
    Exit;
  end;
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, False);
  if mTarget <> nil then
  begin
    mMessages.RemoveMessageGroup(mTarget);
  end;
end;

end.
