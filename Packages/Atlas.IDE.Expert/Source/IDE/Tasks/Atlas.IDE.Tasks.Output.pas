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
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Runs;

type
  TAtlasIdeTaskOutput = class
  public const
    MaxRuns = 20;
    MaxLines = 5000;
  private type
    TEntry = class
      Id: Integer;
      Name: string;
      CommandLine: string;
      TimeoutSec: Integer;
      Running: Boolean;
      Run: TAtlasTaskRun;
      Lines: TArray<string>;
      /// <summary>Je Zeile der Index in Findings, -1 ohne.</summary>
      LineFinding: TArray<Integer>;
      Findings: TAtlasTaskFindings;
      Dropped: Integer;
    end;
  private
    FEntries: TObjectList<TEntry>;
    FOnlyFindings: Boolean;
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
  Vcl.Graphics,
  ToolsAPI,
  Atlas.Core.Style.Palette,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.UI.Strings,
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

function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  Name: string;
begin
  Name := TAtlasStrings.Text(TAtlasTextId.TasksGroup);
  Result := AMessages.GetGroup(Name);
  if (Result = nil) and ACreate then
    Result := AMessages.AddMessageGroup(Name);
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
  Area: TRect;
begin
  Area := Rect;
  Canvas.Font.Style := [fsBold];
  if FColor <> clNone then
    Canvas.Font.Color := FColor;
  Canvas.TextRect(Area, Area.Left + 2, Area.Top, FText);
end;

function THeaderMessage.CalcRect(Canvas: TCanvas; MaxWidth: Integer; Wrap: Boolean): TRect;
begin
  Canvas.Font.Style := [fsBold];
  Result := System.Types.Rect(0, 0, Canvas.TextWidth(FText) + 4, Canvas.TextHeight(FText) + 2);
end;

{ TAtlasIdeTaskOutput }

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
  Entry: TEntry;
begin
  for Entry in FEntries do
    if Entry.Id = AId then
      Exit(Entry);
  Result := nil;
end;

procedure TAtlasIdeTaskOutput.SetOnlyFindings(AValue: Boolean);
begin
  if FOnlyFindings = AValue then
    Exit;
  FOnlyFindings := AValue;
  Render;
end;

procedure TAtlasIdeTaskOutput.AddHeader(AEntry: TEntry);
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Colors: TAtlasColors;
  Color: TColor;
  Text: string;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, True);
  if Target = nil then
    Exit;
  if AEntry.Running then
  begin
    Text := TAtlasTaskTexts.Running(AEntry.Name, AEntry.CommandLine);
    Color := clNone;
  end
  else
  begin
    Text := TAtlasTaskTexts.Header(AEntry.Run, AEntry.TimeoutSec);
    Colors := TAtlasIdeStyle.Colors;
    if AEntry.Run.ExitedCleanly then
      Color := TColor(Colors.Add)
    else
      Color := TColor(Colors.Error);
  end;
  Messages.AddCustomMessage(THeaderMessage.Create(Text, Color) as IOTACustomMessage, Target);
end;

procedure TAtlasIdeTaskOutput.AddLine(AEntry: TEntry; AIndex: Integer);
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Finding: TAtlasTaskFinding;
  LineRef: Pointer;
  Line: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, True);
  if Target = nil then
    Exit;
  if (AIndex <= High(AEntry.LineFinding)) and (AEntry.LineFinding[AIndex] >= 0) then
  begin
    Finding := AEntry.Findings[AEntry.LineFinding[AIndex]];
    if Finding.FileName <> '' then
    begin
      Line := Finding.Line;
      if Line < 1 then
        Line := 1;
      Messages.AddToolMessage(Finding.FileName, AEntry.Lines[AIndex], AEntry.Name, Line, Finding.Column, nil,
        LineRef, Target);
      Exit;
    end;
  end
  else if FOnlyFindings then
    Exit;
  Messages.AddTitleMessage('  ' + AEntry.Lines[AIndex], Target);
end;

procedure TAtlasIdeTaskOutput.Started(AId: Integer; const AName, ACommandLine: string; ATimeoutSec: Integer;
  AShow: Boolean);
var
  Entry: TEntry;
  Messages: IOTAMessageServices;
begin
  Entry := TEntry.Create;
  Entry.Id := AId;
  Entry.Name := AName;
  Entry.CommandLine := ACommandLine;
  Entry.TimeoutSec := ATimeoutSec;
  Entry.Running := True;
  FEntries.Add(Entry);
  while FEntries.Count > MaxRuns do
    FEntries.Delete(0);
  AddHeader(Entry);
  if AShow and Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.ShowMessageView(Group(Messages, True));
end;

procedure TAtlasIdeTaskOutput.Lines(AId: Integer; const ALines: TArray<string>; const AFindings: TAtlasTaskFindings);
var
  Entry: TEntry;
  Finding: TAtlasTaskFinding;
  Line: string;
  First, Index: Integer;
begin
  Entry := Find(AId);
  if Entry = nil then
    Exit;
  First := Length(Entry.Lines);
  for Line in ALines do
    if Length(Entry.Lines) < MaxLines then
    begin
      Entry.Lines := Entry.Lines + [Line];
      Entry.LineFinding := Entry.LineFinding + [-1];
    end
    else
      Inc(Entry.Dropped);
  for Finding in AFindings do
  begin
    Entry.Findings := Entry.Findings + [Finding];
    if (Finding.OutputLine >= 0) and (Finding.OutputLine <= High(Entry.LineFinding)) then
      Entry.LineFinding[Finding.OutputLine] := High(Entry.Findings);
  end;
  for Index := First to High(Entry.Lines) do
    AddLine(Entry, Index);
end;

procedure TAtlasIdeTaskOutput.Finished(AId: Integer; const ARun: TAtlasTaskRun);
var
  Entry: TEntry;
begin
  Entry := Find(AId);
  if Entry = nil then
    Exit;
  Entry.Running := False;
  Entry.Run := ARun;
  Render;
end;

procedure TAtlasIdeTaskOutput.Render;
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Entry: TEntry;
  Index: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, FEntries.Count > 0);
  if Target = nil then
    Exit;
  Messages.ClearMessageGroup(Target);
  for Entry in FEntries do
  begin
    AddHeader(Entry);
    for Index := 0 to High(Entry.Lines) do
      AddLine(Entry, Index);
    if (Entry.Dropped > 0) and not FOnlyFindings then
      Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.TasksMoreLines, [Entry.Dropped]), Target);
  end;
end;

procedure TAtlasIdeTaskOutput.Clear;
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
begin
  FEntries.Clear;
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, False);
  if Target <> nil then
    Messages.RemoveMessageGroup(Target);
end;

end.
