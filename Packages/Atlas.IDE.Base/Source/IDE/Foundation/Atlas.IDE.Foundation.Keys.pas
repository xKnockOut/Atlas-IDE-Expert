unit Atlas.IDE.Foundation.Keys;

// Tastenkürzel von Atlas in der IDE (#494): vor dem Belegen prüfen, ob die
// IDE oder eine andere Erweiterung die Taste schon nutzt (Aktionen aus
// INTAServices.ActionList, bekannte Editor-Belegungen). Ohne Vorrang bleibt die
// fremde Belegung aktiv und Atlas meldet den Konflikt in der Meldungsansicht.
// Beim Start außerdem Hinweis auf Erweiterungen mit eigener Vervollständigung.
// Nach dem Installieren oder Entfernen von Packages prüft Atlas erneut
// (WatchPackages). TAtlasIdeKeyBinding belegt eine einzelne Taste für eine
// Aktion, etwa die eigenen Tasten für Vervollständigung und Parameter-Hint.
// Gemeldete Tasten merkt sich Reported, damit die Prüfung beim Start (#520)
// denselben Konflikt nicht ein zweites Mal meldet.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

type
  /// <summary>Eine Taste von Atlas für eine Aktion; Rebind belegt sie nach den Regeln von #494.</summary>
  TAtlasIdeKeyBinding = class
  private type
    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TAtlasIdeKeyBinding;
      procedure Execute(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FName: string;
    FDisplayName: string;
    FAction: TProc;
    FFeature: TAtlasFeature;
    FBinding: TBinding;
    // Hält das Binding am Leben: Abmelden gibt die Referenz der IDE frei.
    FBindingRef: IOTAKeyboardBinding;
    FIndex: Integer;
    FKey: Word;
  public
    /// <summary>AFeature: Fehler in AAction zählt die Sicherung dieses Features (#493).</summary>
    constructor Create(const AName, ADisplayName: string; AFeature: TAtlasFeature; const AAction: TProc);
    destructor Destroy; override;
    /// <summary>AKey (0 = keine) belegen, bei fremder Belegung nur mit APriority; AWhat für die Meldung.</summary>
    procedure Rebind(AKey: Word; APriority: Boolean; const AWhat: string);
    /// <summary>Belegte Taste; 0 ohne.</summary>
    property Key: Word read FKey;
  end;

  TAtlasIdeKeys = class
  private type
    TPackageWatch = class(TNotifierObject, IOTAIDENotifier)
    private
      FChanged: TProc;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
      procedure AfterCompile(Succeeded: Boolean);
    end;
  private class var
    FReported: TArray<string>;
    // Tasten, zu denen schon ein Konflikt gemeldet ist (#520).
    FReportedKeys: TArray<Word>;
    // Schon gemeldete Erweiterungen mit eigener Vervollständigung: nach Package-Änderungen nur neue melden.
    FForeignReported: TArray<string>;
    FWatch: TPackageWatch;
    FWatchIndex: Integer;
  public
    /// <summary>Wer belegt AShortCut außer Atlas? '' wenn frei.</summary>
    class function Owner(AShortCut: Word): string; static;
    /// <summary>Soll Atlas AShortCut für AWhat belegen? Meldet einen Konflikt einmal je Taste und Besitzer.</summary>
    class function Decide(AShortCut: Word; APriority: Boolean; const AWhat: string): Boolean; static;
    /// <summary>ABinding (neu) anmelden bzw. abmelden; AIndex -1 = nicht angemeldet.</summary>
    class procedure Bind(const ABinding: IOTAKeyboardBinding; var AIndex: Integer); static;
    class procedure Unbind(var AIndex: Integer); static;
    /// <summary>Geladene Erweiterungen mit eigener Vervollständigung (für die Seite „Tastenkonflikte“).</summary>
    class function ForeignCompletions: TArray<string>; static;
    /// <summary>Hinweis, wenn eine andere Erweiterung eine eigene Vervollständigung mitbringt.</summary>
    class procedure ReportForeignCompletion; static;
    class procedure AddMessage(const AText: string); static;
    /// <summary>Zu AShortCut ist in dieser Sitzung schon ein Konflikt gemeldet (#494, #520).</summary>
    class function Reported(AShortCut: Word): Boolean; static;
    class procedure MarkReported(AShortCut: Word); static;
    /// <summary>AChanged im Hauptthread aufrufen, sobald Packages installiert oder entfernt werden.</summary>
    class procedure WatchPackages(const AChanged: TProc); static;
    class procedure UnwatchPackages; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  Winapi.PsAPI,
  Vcl.ActnList,
  Vcl.Menus,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.UI.Strings;

{ TAtlasIdeKeyBinding.TBinding }

function TAtlasIdeKeyBinding.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TAtlasIdeKeyBinding.TBinding.GetDisplayName: string;
begin
  if FOwner <> nil then
  begin
    Result := FOwner.FDisplayName;
  end
  else
  begin
    Result := 'Atlas';
  end;
end;

function TAtlasIdeKeyBinding.TBinding.GetName: string;
begin
  if FOwner <> nil then
  begin
    Result := FOwner.FName;
  end
  else
  begin
    Result := 'Atlas.Key';
  end;
end;

procedure TAtlasIdeKeyBinding.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if (FOwner <> nil) and (FOwner.FKey <> 0) then
  begin
    BindingServices.AddKeyBinding([FOwner.FKey], Execute, nil);
  end;
end;

procedure TAtlasIdeKeyBinding.TBinding.Execute(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if (FOwner <> nil) and Assigned(FOwner.FAction) then
  begin
    // Keine Exception an die IDE (#493).
    TAtlasGuard.Run(FOwner.FFeature, FOwner.FAction);
  end;
end;

{ TAtlasIdeKeyBinding }

constructor TAtlasIdeKeyBinding.Create(const AName, ADisplayName: string; AFeature: TAtlasFeature;
  const AAction: TProc);
begin
  inherited Create;
  FName := AName;
  FFeature := AFeature;
  FDisplayName := ADisplayName;
  FAction := AAction;
  FIndex := -1;
  FBinding := TBinding.Create;
  FBinding.FOwner := Self;
  FBindingRef := FBinding;
end;

destructor TAtlasIdeKeyBinding.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  FBinding.FOwner := nil;
  TAtlasIdeKeys.Unbind(FIndex);
  FBindingRef := nil;
  inherited Destroy;
end;

procedure TAtlasIdeKeyBinding.Rebind(AKey: Word; APriority: Boolean; const AWhat: string);
var
  mKey: Word;
begin
  mKey := AKey;
  if not TAtlasIdeKeys.Decide(mKey, APriority, AWhat) then
  begin
    mKey := 0;
  end;
  if (mKey = FKey) and ((FIndex >= 0) = (mKey <> 0)) then
  begin
    Exit;
  end;
  FKey := mKey;
  if FKey = 0 then
  begin
    TAtlasIdeKeys.Unbind(FIndex);
  end
  else
  begin
    TAtlasIdeKeys.Bind(FBindingRef, FIndex);
  end;
end;

{ TAtlasIdeKeys.TPackageWatch }

procedure TAtlasIdeKeys.TPackageWatch.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Changed: TProc;
begin
  if not (NotifyCode in [ofnPackageInstalled, ofnPackageUninstalled]) or not Assigned(FChanged) then
  begin
    Exit;
  end;
  Changed := FChanged;
  // Nach der Meldung: Das Package ist dann fertig geladen bzw. entladen.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
    procedure
    begin
      // Keine Exception an die IDE (#493).
      TAtlasGuard.Run(TAtlasFeature.Settings, Changed);
    end);
end;

procedure TAtlasIdeKeys.TPackageWatch.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeKeys.TPackageWatch.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeKeys }

class procedure TAtlasIdeKeys.WatchPackages(const AChanged: TProc);
var
  Services: IOTAServices;
begin
  UnwatchPackages;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Exit;
  end;
  FWatch := TPackageWatch.Create;
  FWatch.FChanged := AChanged;
  FWatchIndex := Services.AddNotifier(FWatch);
end;

class procedure TAtlasIdeKeys.UnwatchPackages;
var
  Services: IOTAServices;
begin
  if FWatch = nil then
  begin
    Exit;
  end;
  FWatch.FChanged := nil;
  // RemoveNotifier gibt die Referenz der IDE frei und damit FWatch.
  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    Services.RemoveNotifier(FWatchIndex);
  end;
  FWatch := nil;
end;

/// <summary>Liegt AShortCut als Haupt- oder Zweittaste auf AAction?</summary>
function HasShortCut(AAction: TCustomAction; AShortCut: Word): Boolean;
var
  mSecondary: Integer;
begin
  Result := AAction.ShortCut = AShortCut;
  for mSecondary := 0 to AAction.SecondaryShortCuts.Count - 1 do
  begin
    Result := Result or (AAction.SecondaryShortCuts.ShortCuts[mSecondary] = AShortCut);
  end;
end;

/// <summary>Name der IDE-Aktion (nicht von Atlas) mit AShortCut; '' ohne.</summary>
function ActionOwner(AShortCut: Word): string;
var
  mServices: INTAServices;
  mIndex: Integer;
  mAction: TCustomAction;
begin
  Result := '';
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    if mServices.ActionList.Actions[mIndex] is TCustomAction then
    begin
      mAction := TCustomAction(mServices.ActionList.Actions[mIndex]);
      if not SameText(mAction.Category, 'Atlas') and HasShortCut(mAction, AShortCut) then
      begin
        Exit(StripHotkey(mAction.Caption));
      end;
    end;
  end;
end;

class function TAtlasIdeKeys.Owner(AShortCut: Word): string;
begin
  Result := '';
  if AShortCut = 0 then
  begin
    Exit;
  end;
  Result := ActionOwner(AShortCut);
  if Result = '' then
  begin
    Result := TAtlasKeyConflicts.OwnerOf(AShortCut, TAtlasKeyConflicts.KnownIdeKeys);
  end;
end;

class function TAtlasIdeKeys.Decide(AShortCut: Word; APriority: Boolean; const AWhat: string): Boolean;
var
  Holder, Key, Seen: string;
begin
  Holder := Owner(AShortCut);
  Result := TAtlasKeyConflicts.ShouldBind(AShortCut, Holder, APriority);
  if Result or (Holder = '') then
  begin
    Exit;
  end;
  Key := ShortCutToText(AShortCut) + '|' + Holder;
  for Seen in FReported do
  begin
    if Seen = Key then
    begin
      Exit;
    end;
  end;
  FReported := FReported + [Key];
  AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyConflict, [ShortCutToText(AShortCut), Holder, AWhat]));
  MarkReported(AShortCut);
end;

class function TAtlasIdeKeys.Reported(AShortCut: Word): Boolean;
var
  Key: Word;
begin
  Result := False;
  for Key in FReportedKeys do
  begin
    if Key = AShortCut then
    begin
      Exit(True);
    end;
  end;
end;

class procedure TAtlasIdeKeys.MarkReported(AShortCut: Word);
begin
  if not Reported(AShortCut) then
  begin
    FReportedKeys := FReportedKeys + [AShortCut];
  end;
end;

class procedure TAtlasIdeKeys.Bind(const ABinding: IOTAKeyboardBinding; var AIndex: Integer);
var
  Keyboard: IOTAKeyboardServices;
begin
  Unbind(AIndex);
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    AIndex := Keyboard.AddKeyboardBinding(ABinding);
  end;
end;

class procedure TAtlasIdeKeys.Unbind(var AIndex: Integer);
var
  Keyboard: IOTAKeyboardServices;
begin
  if (AIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    Keyboard.RemoveKeyboardBinding(AIndex);
  end;
  AIndex := -1;
end;

class procedure TAtlasIdeKeys.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
  begin
    Group := Messages.AddMessageGroup('Atlas');
  end;
  Messages.AddTitleMessage(AText, Group);
end;

class function TAtlasIdeKeys.ForeignCompletions: TArray<string>;
var
  Modules: array[0..1023] of HMODULE;
  Needed: DWORD;
  Index: Integer;
  Names: TArray<string>;
  Name: array[0..MAX_PATH] of Char;
begin
  Result := nil;
  Names := nil;
  if not EnumProcessModules(GetCurrentProcess, @Modules[0], SizeOf(Modules), Needed) then
  begin
    Exit;
  end;
  for Index := 0 to Integer(Needed div SizeOf(HMODULE)) - 1 do
  begin
    if (Index <= High(Modules)) and (GetModuleFileName(Modules[Index], Name, Length(Name)) > 0) then
    begin
      Names := Names + [string(Name)];
    end;
  end;
  Result := TAtlasKeyConflicts.CompletionExtensions(Names);
end;

class procedure TAtlasIdeKeys.ReportForeignCompletion;
var
  Extension, Seen: string;
  Known: Boolean;
begin
  for Extension in ForeignCompletions do
  begin
    Known := False;
    for Seen in FForeignReported do
    begin
      if SameText(Seen, Extension) then
      begin
        Known := True;
      end;
    end;
    if Known then
    begin
      Continue;
    end;
    FForeignReported := FForeignReported + [Extension];
    AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ForeignCompletion, [Extension]));
  end;
end;

end.
