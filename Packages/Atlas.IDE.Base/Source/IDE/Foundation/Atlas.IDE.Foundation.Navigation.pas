unit Atlas.IDE.Foundation.Navigation;

// Zu einer Stelle springen (#400, #588): Datei öffnen, Editor zeigen, Cursor setzen. Foundation des Plugins
//: bis dahin TAtlasEditorHover.GoToLocation; Ergebnisfenster, Umbenennen, Vervollständigung, Befehle
// und Unit-Suche importierten dafür den Hover. Nur im Hauptthread.
// Ersatz-Units des Servers (atlas-ide:…, nur aus der RTTI der Packages) gibt es nicht als Datei: kein Sprung
// dorthin, die IDE legte sonst einen leeren Reiter unter diesem Namen an.
// Klick auf eigene Elemente im Editor (Marken, Inlay-Hinweise, Kopf des Sticky Scroll, Symbole der Gutter-Spalte)
// über AfterClick bzw. JumpAfterClick: Der Editor behandelt denselben Klick selbst (im Text beginnt er eine
// Markierung, in der Gutter-Leiste markiert er die Zeile). Gehandelt wird erst nach dem Loslassen der Maustaste,
// davor wird seine Markierung verworfen.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard;

type
  TAtlasIdeNavigation = class
  public
    /// <summary>Zeigt AFileName (öffnet sie nur, wenn sie noch nicht offen ist) und setzt den Cursor auf
    /// ALine/ACharacter (0-basiert).</summary>
    class procedure GoToLocation(const AFileName: string; ALine, ACharacter: Integer); static;
    /// <summary>GoToLocation nach einem Klick in den Text des Editors: erst, wenn die linke Maustaste wieder oben
    /// ist, danach eine Markierung verwerfen. Solange sie gedrückt ist, zieht der Editor ab der Klickstelle eine
    /// Markierung bis zur Sprungstelle auf. AThen läuft nach dem Sprung, geschützt über AFeature; nur aus Base
    /// übergeben, ein Modul kann bis dahin entladen sein. Ein neuer Klick ersetzt einen noch wartenden Sprung.
    /// </summary>
    class procedure JumpAfterClick(AFeature: TAtlasFeature; const AFileName: string; ALine, ACharacter: Integer;
      const AThen: TProc); static;
    /// <summary>AAction nach einem Klick auf ein eigenes Element im Editor: erst, wenn die linke Maustaste wieder
    /// oben ist, und nachdem die Markierung verworfen ist, die der Editor für denselben Klick angelegt hat
    /// (Text bis zur Maus, in der Gutter-Leiste die ganze Zeile). Geschützt über AFeature. AOwner: Wer AAction
    /// übergibt, ruft vor seiner Freigabe CancelAfterClick(Self); nur aus Base, ein Modul kann bis dahin entladen
    /// sein. Ein neuer Klick ersetzt einen noch wartenden.</summary>
    class procedure AfterClick(AFeature: TAtlasFeature; AOwner: TObject; const AAction: TProc); static;
    /// <summary>Verwirft einen noch wartenden Klick von AOwner.</summary>
    class procedure CancelAfterClick(AOwner: TObject); static;
    /// <summary>Zeigt AFileName ohne Sprung; öffnet sie nur, wenn sie noch nicht offen ist. False, wenn die IDE sie
    /// nicht öffnen kann.</summary>
    class function ShowFile(const AFileName: string): Boolean; static;
    /// <summary>Setzt den Cursor im oberen Editor auf ALine/ACharacter (0-basiert), z. B. für den Sprung
    /// einer Code-Aktion zur Freigabe (#915).</summary>
    class procedure GoToPosition(ALine, ACharacter: Integer); static;
    /// <summary>Öffnet AFileName, markiert die ganze Zeile ALine (0-basiert) und setzt den Cursor an ihren Anfang,
    /// z. B. für den Sprung in eigenen Code nach einer Exception (#578).</summary>
    class procedure MarkLine(const AFileName: string; ALine: Integer); static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.IdeMembers;

type
  /// <summary>Ein wartender Klick; der Takt prüft, ob die Maustaste oben ist.</summary>
  TPendingClick = class
  private
    FTimer: TTimer;
    FFeature: TAtlasFeature;
    FOwner: TObject;
    FAction: TProc;
    procedure Tick(Sender: TObject);
  public
    destructor Destroy; override;
    procedure Start(AFeature: TAtlasFeature; AOwner: TObject; const AAction: TProc);
    procedure Cancel(AOwner: TObject);
  end;

const
  // Takt, in dem geprüft wird, ob die Maustaste oben ist (ms).
  cClickInterval = 20;

var
  GPendingClick: TPendingClick;

/// <summary>Markierung der oberen Ansicht verwerfen.</summary>
procedure ResetTopBlock;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
    if (mView <> nil) and (mView.Block <> nil) then
    begin
      mView.Block.Reset;
    end;
  end;
end;

{ TPendingClick }

destructor TPendingClick.Destroy;
begin
  FTimer.Free;
  FAction := nil;
  inherited Destroy;
end;

procedure TPendingClick.Start(AFeature: TAtlasFeature; AOwner: TObject; const AAction: TProc);
begin
  FFeature := AFeature;
  FOwner := AOwner;
  FAction := AAction;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Interval := cClickInterval;
    FTimer.OnTimer := Tick;
  end;
  FTimer.Enabled := True;
end;

procedure TPendingClick.Cancel(AOwner: TObject);
begin
  // Assigned statt <> nil: Delphi würde die Methodenreferenz aufrufen und das Ergebnis vergleichen (E2008/E2015).
  if Assigned(FAction) and (FOwner = AOwner) then
  begin
    FTimer.Enabled := False;
    FAction := nil;
    FOwner := nil;
  end;
end;

procedure TPendingClick.Tick(Sender: TObject);
var
  mAction: TProc;
begin
  if GetAsyncKeyState(VK_LBUTTON) < 0 then
  begin
    Exit;
  end;
  FTimer.Enabled := False;
  mAction := FAction;
  FAction := nil;
  FOwner := nil;
  TAtlasGuard.Run(FFeature,
    procedure
    begin
      // Was der Editor für denselben Klick markiert hat, verwerfen.
      ResetTopBlock;
      if Assigned(mAction) then
      begin
        mAction();
      end;
    end);
end;

/// <summary>Modul von AFileName; öffnet die Datei nur, wenn sie noch nicht offen ist. OpenFile öffnete sie sonst
/// jedes Mal neu (Doppelklick in „Atlas-Prüfung“), bei Formular-Units samt Designer. nil, wenn das scheitert.
/// </summary>
function OpenModule(const AFileName: string): IOTAModule;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if TAtlasIdeMembers.IsIdePath(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  Result := mModules.FindModule(AFileName);
  if (Result = nil) and Supports(BorlandIDEServices, IOTAActionServices, mActions) and
    mActions.OpenFile(AFileName) then
  begin
    Result := mModules.FindModule(AFileName);
  end;
end;

/// <summary>Erster Quelltexteditor des Moduls; nil ohne.</summary>
function SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTASourceEditor, Result) then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

{ TAtlasIdeNavigation }

class procedure TAtlasIdeNavigation.GoToLocation(const AFileName: string; ALine, ACharacter: Integer);
var
  mModule: IOTAModule;
  mEditor: IOTASourceEditor;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  // Schon offen: nur den Reiter zeigen und springen.
  mModule := OpenModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  mEditor := SourceEditorOf(mModule);
  if mEditor = nil then
  begin
    Exit;
  end;
  mEditor.Show;
  if mEditor.EditViewCount = 0 then
  begin
    Exit;
  end;
  mView := mEditor.EditViews[0];
  mCursor.Line := ALine + 1;
  mCursor.Col := ACharacter + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class function TAtlasIdeNavigation.ShowFile(const AFileName: string): Boolean;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
  mEditor: IOTASourceEditor;
begin
  Result := False;
  if TAtlasIdeMembers.IsIdePath(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  // Wie GoToLocation: OpenFile öffnete eine offene Datei erneut, bei Formular-Units samt Designer.
  mModule := mModules.FindModule(AFileName);
  if mModule <> nil then
  begin
    for mIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mIndex], IOTASourceEditor, mEditor) then
      begin
        mEditor.Show;
        Exit(True);
      end;
    end;
  end;
  Result := Supports(BorlandIDEServices, IOTAActionServices, mActions) and mActions.OpenFile(AFileName);
end;

class procedure TAtlasIdeNavigation.GoToPosition(ALine, ACharacter: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if mView = nil then
  begin
    Exit;
  end;
  mCursor.Line := ALine + 1;
  mCursor.Col := ACharacter + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class procedure TAtlasIdeNavigation.MarkLine(const AFileName: string; ALine: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  GoToLocation(AFileName, ALine, 0);
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  // Zeilenanfang markieren, Cursor an den Anfang der nächsten Zeile, Ende markieren, Cursor zurück.
  mView.Block.Style := btNonInclusive;
  mCursor.Line := ALine + 1;
  mCursor.Col := 1;
  mView.CursorPos := mCursor;
  mView.Block.BeginBlock;
  mCursor.Line := ALine + 2;
  mView.CursorPos := mCursor;
  mView.Block.EndBlock;
  mCursor.Line := ALine + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class procedure TAtlasIdeNavigation.JumpAfterClick(AFeature: TAtlasFeature; const AFileName: string; ALine,
  ACharacter: Integer; const AThen: TProc);
var
  mFileName: string;
  mLine, mCharacter: Integer;
  mThen: TProc;
begin
  mFileName := AFileName;
  mLine := ALine;
  mCharacter := ACharacter;
  mThen := AThen;
  AfterClick(AFeature, nil,
    procedure
    begin
      GoToLocation(mFileName, mLine, mCharacter);
      if Assigned(mThen) then
      begin
        mThen();
      end;
    end);
end;

class procedure TAtlasIdeNavigation.AfterClick(AFeature: TAtlasFeature; AOwner: TObject; const AAction: TProc);
begin
  if GPendingClick = nil then
  begin
    GPendingClick := TPendingClick.Create;
  end;
  GPendingClick.Start(AFeature, AOwner, AAction);
end;

class procedure TAtlasIdeNavigation.CancelAfterClick(AOwner: TObject);
begin
  if GPendingClick <> nil then
  begin
    GPendingClick.Cancel(AOwner);
  end;
end;

initialization

finalization
  FreeAndNil(GPendingClick);

end.
