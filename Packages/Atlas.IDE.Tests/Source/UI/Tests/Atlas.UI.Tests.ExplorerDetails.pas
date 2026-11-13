unit Atlas.UI.Tests.ExplorerDetails;

// Unterer Teil des Fensters „Atlas-Tests“ (#1776, #2168), reine VCL: Reiter
// „Einzelheiten“ (Meldung, erwartet, erhalten, Stacktrace) und „Protokoll (n)“
// (Zeilen des Tests aus Atlas.Core.Tests.Log) über einer Liste. Zeilen mit
// Fundstelle öffnen sich per Doppelklick bzw. Enter; „Kopieren“ und Strg+C
// legen das ganze Protokoll in die Zwischenablage. Ohne tests.log gibt es den
// Reiter „Protokoll“ nicht. Die Reiter brauchen ein Fenster: gefüllt wird mit
// Fill, sobald der Frame eins hat.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Tests.Explorer;

type
  TAtlasTestsExplorerDetails = class(TComponent)
  private
    FFrame: TCustomFrame;
    FPanel: TPanel;
    FTabs: TTabControl;
    FList: TListBox;
    FCopy: TButton;
    FDetailLines: TArray<TAtlasTestStackLine>;
    FLogLines: TArray<TAtlasTestStackLine>;
    FLogCount: Integer;
    FLogEnabled: Boolean;
    FOnOpenLine: TProc<string, Integer>;
    function Scaled96(AValue: Integer): Integer;
    function ShowsLog: Boolean;
    function Shown: TArray<TAtlasTestStackLine>;
    procedure FillTabs;
    procedure FillList;
    procedure TabChange(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CopyClick(Sender: TObject);
    procedure OpenLine;
  public
    /// <summary>Teil unten auf AFrame anlegen (alBottom, AHeight in 96 dpi).</summary>
    constructor Create(AFrame: TCustomFrame; AHeight: Integer); reintroduce;
    /// <summary>Einzelheiten zum gewählten Test.</summary>
    procedure SetDetails(const ALines: TArray<TAtlasTestStackLine>);
    /// <summary>Protokoll zum gewählten Test mit der Zahl ACount für den Reiter; AEnabled False = kein Reiter.
    /// </summary>
    procedure SetLog(const ALines: TArray<TAtlasTestStackLine>; ACount: Integer; AEnabled: Boolean);
    /// <summary>Reiter und Liste füllen (braucht ein Fenster).</summary>
    procedure Fill;
    /// <summary>Text des Protokolls für die Zwischenablage.</summary>
    function LogText: string;
    property Panel: TPanel read FPanel;
    property List: TListBox read FList;
    property Tabs: TTabControl read FTabs;
    property OnOpenLine: TProc<string, Integer> read FOnOpenLine write FOnOpenLine;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.UI.Tests.Strings;

const
  cBasePpi = 96;
  cGap = 6;
  cCopyHeight = 28;
  cCopyWidth = 110;
  /// <summary>Index der Reiter.</summary>
  cDetailsTab = 0;
  cLogTab = 1;

{ TAtlasTestsExplorerDetails }

constructor TAtlasTestsExplorerDetails.Create(AFrame: TCustomFrame; AHeight: Integer);
var
  mStrip: TPanel;
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  FPanel := TPanel.Create(FFrame);
  FPanel.Height := Scaled96(AHeight);
  FPanel.BevelOuter := bvNone;
  FPanel.Align := alBottom;
  FPanel.Parent := FFrame;
  mStrip := TPanel.Create(FFrame);
  mStrip.Height := Scaled96(cCopyHeight + cGap);
  mStrip.BevelOuter := bvNone;
  mStrip.Align := alBottom;
  mStrip.Parent := FPanel;
  FCopy := TButton.Create(FFrame);
  FCopy.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerLogCopy);
  FCopy.SetBounds(Scaled96(cGap), Scaled96(cGap) div 2, Scaled96(cCopyWidth), Scaled96(cCopyHeight));
  FCopy.OnClick := CopyClick;
  FCopy.Visible := False;
  FCopy.Parent := mStrip;
  FTabs := TTabControl.Create(FFrame);
  FTabs.Align := alClient;
  FTabs.OnChange := TabChange;
  FTabs.Parent := FPanel;
  FList := TListBox.Create(FFrame);
  FList.Align := alClient;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.Parent := FTabs;
end;

function TAtlasTestsExplorerDetails.Scaled96(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FFrame.CurrentPPI, cBasePpi);
end;

function TAtlasTestsExplorerDetails.ShowsLog: Boolean;
begin
  Result := FLogEnabled and FTabs.HandleAllocated and (FTabs.TabIndex = cLogTab);
end;

function TAtlasTestsExplorerDetails.Shown: TArray<TAtlasTestStackLine>;
begin
  Result := FDetailLines;
  if ShowsLog then
  begin
    Result := FLogLines;
  end;
end;

procedure TAtlasTestsExplorerDetails.SetDetails(const ALines: TArray<TAtlasTestStackLine>);
begin
  FDetailLines := ALines;
  if FFrame.HandleAllocated then
  begin
    FillList;
  end;
end;

procedure TAtlasTestsExplorerDetails.SetLog(const ALines: TArray<TAtlasTestStackLine>; ACount: Integer;
  AEnabled: Boolean);
begin
  FLogLines := ALines;
  FLogCount := ACount;
  FLogEnabled := AEnabled;
  if FFrame.HandleAllocated then
  begin
    Fill;
  end;
end;

procedure TAtlasTestsExplorerDetails.Fill;
begin
  FillTabs;
  FillList;
end;

procedure TAtlasTestsExplorerDetails.FillTabs;
var
  mIndex: Integer;
begin
  FTabs.HandleNeeded;
  mIndex := FTabs.TabIndex;
  FTabs.Tabs.BeginUpdate;
  try
    FTabs.Tabs.Clear;
    FTabs.Tabs.Add(TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailsTab));
    if FLogEnabled then
    begin
      FTabs.Tabs.Add(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ExplorerLogTab, [FLogCount]));
    end;
  finally
    FTabs.Tabs.EndUpdate;
  end;
  if (mIndex < 0) or (mIndex >= FTabs.Tabs.Count) then
  begin
    mIndex := cDetailsTab;
  end;
  FTabs.TabIndex := mIndex;
end;

procedure TAtlasTestsExplorerDetails.FillList;
var
  mLine: TAtlasTestStackLine;
begin
  FList.HandleNeeded;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mLine in Shown do
    begin
      FList.Items.Add(mLine.Text);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  FCopy.Visible := ShowsLog;
end;

procedure TAtlasTestsExplorerDetails.TabChange(Sender: TObject);
begin
  FillList;
end;

procedure TAtlasTestsExplorerDetails.OpenLine;
var
  mIndex: Integer;
  mLines: TArray<TAtlasTestStackLine>;
begin
  mIndex := FList.ItemIndex;
  mLines := Shown;
  if (mIndex < 0) or (mIndex > High(mLines)) or (mLines[mIndex].FileName = '') then
  begin
    Exit;
  end;
  if Assigned(FOnOpenLine) then
  begin
    FOnOpenLine(mLines[mIndex].FileName, mLines[mIndex].Line);
  end;
end;

procedure TAtlasTestsExplorerDetails.ListDblClick(Sender: TObject);
begin
  OpenLine;
end;

procedure TAtlasTestsExplorerDetails.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    OpenLine;
  end
  else if (Key = Ord('C')) and (Shift = [ssCtrl]) and ShowsLog then
  begin
    Key := 0;
    CopyClick(Sender);
  end;
end;

function TAtlasTestsExplorerDetails.LogText: string;
var
  mLine: TAtlasTestStackLine;
begin
  Result := '';
  for mLine in FLogLines do
  begin
    Result := Result + mLine.Text + sLineBreak;
  end;
end;

procedure TAtlasTestsExplorerDetails.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := LogText;
end;

end.
