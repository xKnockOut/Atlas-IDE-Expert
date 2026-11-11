unit Atlas.IDE.Settings.OptionsDialog;

// Tools › Optionen der IDE aus Atlas heraus öffnen und darin springen (#628,
// #1903): Dialog über IOTAEnvironmentOptions140.EditOptions auf einer Seite
// öffnen, sonst über Aktion bzw. Menüpunkt „Optionen…“; im offenen Dialog den
// Knoten Atlas › … wählen. Der Baum des Dialogs ist seit Delphi 13 eine eigene
// Ableitung von TCustomTreeView und legt Unterknoten erst beim Aufklappen an.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls;

type
  /// <summary>Sucht im offenen Optionsdialog die Seite „Atlas“ und wählt sie (#628).</summary>
  TAtlasOptionsSelector = class
  private const
    cIntervalMs = 200;
    cMaxTries = 50;
  private
    FTimer: TTimer;
    FTries: Integer;
    FPending: TFunc<Boolean>;
    procedure Tick(Sender: TObject);
  public
    /// <summary>APending: Ist noch eine Einstellung zum Zeigen vorgemerkt? Sonst hört die Suche auf.</summary>
    constructor Create(const APending: TFunc<Boolean>);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    /// <summary>Erster Baum unter AParent; nil ohne.</summary>
    class function FindTree(AParent: TWinControl): TCustomTreeView; static;
  end;

  TAtlasIdeOptionsDialog = class
  public
    /// <summary>Tools › Optionen öffnen, wenn möglich gleich auf der Seite ACaption; False, wenn weder die IDE
    /// das anbietet noch Aktion oder Menüpunkt „Optionen…“ zu finden sind.</summary>
    class function Open(const ACaption: string): Boolean; static;
    /// <summary>Wählt im offenen Optionsdialog den Knoten Atlas › APath (#1903). False, wenn sich Baum oder Knoten
    /// nicht finden lassen; dann steht im Protokoll, welche Baumklassen der Dialog hat.</summary>
    class function SelectNode(const APath: TArray<string>): Boolean; static;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.ActnList,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

type
  /// <summary>Zugriff auf Items, das TCustomTreeView geschützt hält (Baum des Optionsdialogs ist eine eigene
  /// Ableitung).
  /// </summary>
  TAtlasTreeAccess = class(TCustomTreeView);

const
  /// <summary>Trenner der Knoten im Protokoll.</summary>
  cPathSeparator = ' › ';

{ TAtlasOptionsSelector }

constructor TAtlasOptionsSelector.Create(const APending: TFunc<Boolean>);
begin
  inherited Create;
  FPending := APending;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cIntervalMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasOptionsSelector.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TAtlasOptionsSelector.Start;
begin
  FTries := 0;
  FTimer.Enabled := True;
end;

procedure TAtlasOptionsSelector.Stop;
begin
  FTimer.Enabled := False;
end;

class function TAtlasOptionsSelector.FindTree(AParent: TWinControl): TCustomTreeView;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    // TCustomTreeView: Delphi 13 nimmt eine eigene Ableitung statt TTreeView (#1903).
    if AParent.Controls[mIndex] is TCustomTreeView then
    begin
      Exit(TCustomTreeView(AParent.Controls[mIndex]));
    end;
    if AParent.Controls[mIndex] is TWinControl then
    begin
      Result := FindTree(TWinControl(AParent.Controls[mIndex]));
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

procedure TAtlasOptionsSelector.Tick(Sender: TObject);
var
  mForm: TCustomForm;
  mTree: TCustomTreeView;
  mNode: TTreeNode;
begin
  try
    Inc(FTries);
    if (FTries > cMaxTries) or not FPending() then
    begin
      Stop;
      Exit;
    end;
    mForm := Screen.ActiveCustomForm;
    if (mForm = nil) or not (fsModal in mForm.FormState) then
    begin
      Exit;
    end;
    mTree := FindTree(mForm);
    if mTree = nil then
    begin
      Exit;
    end;
    // Die Seite heißt „Atlas“ (GetCaption) und hängt unter „Drittanbieter“, nicht oben im Baum.
    for mNode in TAtlasTreeAccess(mTree).Items do
    begin
      if SameText(mNode.Text, 'Atlas') and (mNode.Parent <> nil) then
      begin
        Stop;
        mNode.MakeVisible;
        mTree.Selected := mNode;
        Exit;
      end;
    end;
    // Nicht gefunden: Delphi 13 legt die Unterseiten erst beim Aufklappen an ("Fremdhersteller" zu). Obere
    // Zweige aufklappen und beim nächsten Takt erneut suchen, statt aufzugeben.
    for mNode in TAtlasTreeAccess(mTree).Items do
    begin
      if (mNode.Parent = nil) and mNode.HasChildren and not mNode.Expanded then
      begin
        mNode.Expand(False);
      end;
    end;
  except
    on E: Exception do
    begin
      Stop;
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
    end;
  end;
end;

/// <summary>Klassen der Steuerelemente unter AParent, deren Name „Tree“ enthält (Protokoll, wenn kein Baum passt).
/// </summary>
function TreeLikeClasses(AParent: TWinControl): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    if Pos('TREE', UpperCase(AParent.Controls[mIndex].ClassName)) > 0 then
    begin
      Result := Result + ' ' + AParent.Controls[mIndex].ClassName;
    end;
    if AParent.Controls[mIndex] is TWinControl then
    begin
      Result := Result + TreeLikeClasses(TWinControl(AParent.Controls[mIndex]));
    end;
  end;
end;

/// <summary>Kind von ANode mit dem Text AText; klappt ANode dafür auf, weil Delphi 13 Unterknoten erst beim Aufklappen
/// anlegt. nil, wenn ANode nil ist oder kein Kind passt.</summary>
function ChildNamed(ANode: TTreeNode; const AText: string): TTreeNode;
begin
  Result := nil;
  if ANode = nil then
  begin
    Exit;
  end;
  if not ANode.Expanded then
  begin
    ANode.Expand(False);
  end;
  Result := ANode.getFirstChild;
  while (Result <> nil) and not SameText(Result.Text, AText) do
  begin
    Result := Result.getNextSibling;
  end;
end;

class function TAtlasIdeOptionsDialog.SelectNode(const APath: TArray<string>): Boolean;
var
  mForm: TCustomForm;
  mTree: TCustomTreeView;
  mNode, mAtlas: TTreeNode;
  mText: string;
begin
  Result := False;
  mForm := Screen.ActiveCustomForm;
  if mForm = nil then
  begin
    Exit;
  end;
  mTree := TAtlasOptionsSelector.FindTree(mForm);
  if mTree = nil then
  begin
    TAtlasGuard.Log('Optionen: kein Baum im Dialog zum Springen gefunden; Klassen:' + TreeLikeClasses(mForm)); // german-ok Protokoll
    Exit;
  end;
  mAtlas := nil;
  for mNode in TAtlasTreeAccess(mTree).Items do
  begin
    if SameText(mNode.Text, 'Atlas') and (mNode.Parent <> nil) then
    begin
      mAtlas := mNode;
      Break;
    end;
  end;
  mNode := mAtlas;
  for mText in APath do
  begin
    mNode := ChildNamed(mNode, mText);
  end;
  if mNode = nil then
  begin
    TAtlasGuard.Log(Format('Optionen: Knoten Atlas › %s nicht im Baum %s', // german-ok Protokoll
      [string.Join(cPathSeparator, APath), mTree.ClassName]));
    Exit;
  end;
  mNode.MakeVisible;
  mTree.Selected := mNode;
  Result := True;
end;

/// <summary>Aktion bzw. Menüpunkt „Optionen…“ der IDE ausführen; False, wenn keins zu finden ist.</summary>
function RunOptionsDialog: Boolean;
const
  cActionName = 'ToolsOptionsCommand';
  cItemName = 'ToolsOptionsItem';
var
  mServices: INTAServices;
  mIndex: Integer;

  function FindItem(AItem: TMenuItem): TMenuItem;
  var
    mChild: Integer;
  begin
    Result := nil;
    if SameText(AItem.Name, cItemName) then
    begin
      Exit(AItem);
    end;
    for mChild := 0 to AItem.Count - 1 do
    begin
      Result := FindItem(AItem.Items[mChild]);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;

var
  mItem: TMenuItem;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    Exit;
  end;
  if mServices.ActionList <> nil then
  begin
    for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
    begin
      if SameText(mServices.ActionList.Actions[mIndex].Name, cActionName) then
      begin
        mServices.ActionList.Actions[mIndex].Execute;
        Exit(True);
      end;
    end;
  end;
  if mServices.MainMenu <> nil then
  begin
    mItem := FindItem(mServices.MainMenu.Items);
    if mItem <> nil then
    begin
      mItem.Click;
      Exit(True);
    end;
  end;
end;

/// <summary>Tools › Optionen über IOTAEnvironmentOptions140.EditOptions auf der Seite „Atlas“ öffnen; False, wenn die
/// IDE das nicht anbietet.</summary>
function EditAtlasOptions(const ACaption: string): Boolean;
var
  mServices: IOTAServices;
  mEnvironment: IOTAEnvironmentOptions140;
begin
  Result := Supports(BorlandIDEServices, IOTAServices, mServices) and (mServices.GetEnvironmentOptions <> nil) and
    Supports(mServices.GetEnvironmentOptions, IOTAEnvironmentOptions140, mEnvironment);
  if Result then
  begin
    mEnvironment.EditOptions('', ACaption);
  end;
end;

{ TAtlasIdeOptionsDialog }

class function TAtlasIdeOptionsDialog.Open(const ACaption: string): Boolean;
begin
  Result := EditAtlasOptions(ACaption) or RunOptionsDialog;
end;

end.
