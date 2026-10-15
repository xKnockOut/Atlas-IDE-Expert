unit Atlas.IDE.Commands.Keys;

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
    Result := FOwner.FDisplayName
  else
    Result := 'Atlas';
end;

function TAtlasIdeKeyBinding.TBinding.GetName: string;
begin
  if FOwner <> nil then
    Result := FOwner.FName
  else
    Result := 'Atlas.Key';
end;

procedure TAtlasIdeKeyBinding.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if (FOwner <> nil) and (FOwner.FKey <> 0) then
    BindingServices.AddKeyBinding([FOwner.FKey], Execute, nil);
end;

procedure TAtlasIdeKeyBinding.TBinding.Execute(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if (FOwner <> nil) and Assigned(FOwner.FAction) then
    // Keine Exception an die IDE (#493).
    TAtlasGuard.Run(FOwner.FFeature, FOwner.FAction);
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
  Key: Word;
begin
  Key := AKey;
  if not TAtlasIdeKeys.Decide(Key, APriority, AWhat) then
    Key := 0;
  if (Key = FKey) and ((FIndex >= 0) = (Key <> 0)) then
    Exit;
  FKey := Key;
  if FKey = 0 then
    TAtlasIdeKeys.Unbind(FIndex)
  else
    TAtlasIdeKeys.Bind(FBindingRef, FIndex);
end;

{ TAtlasIdeKeys.TPackageWatch }

procedure TAtlasIdeKeys.TPackageWatch.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  Changed: TProc;
begin
  if not (NotifyCode in [ofnPackageInstalled, ofnPackageUninstalled]) or not Assigned(FChanged) then
    Exit;
  Changed := FChanged;
  // Nach der Meldung: Das Package ist dann fertig geladen bzw. entladen.
  TThread.ForceQueue(nil,
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
    Exit;
  FWatch := TPackageWatch.Create;
  FWatch.FChanged := AChanged;
  FWatchIndex := Services.AddNotifier(FWatch);
end;

class procedure TAtlasIdeKeys.UnwatchPackages;
var
  Services: IOTAServices;
begin
  if FWatch = nil then
    Exit;
  FWatch.FChanged := nil;
  // RemoveNotifier gibt die Referenz der IDE frei und damit FWatch.
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(FWatchIndex);
  FWatch := nil;
end;

class function TAtlasIdeKeys.Owner(AShortCut: Word): string;
var
  Services: INTAServices;
  Index, Secondary: Integer;
  Action: TCustomAction;
begin
  Result := '';
  if AShortCut = 0 then
    Exit;
  if Supports(BorlandIDEServices, INTAServices, Services) and (Services.ActionList <> nil) then
    for Index := 0 to Services.ActionList.ActionCount - 1 do
    begin
      if not (Services.ActionList.Actions[Index] is TCustomAction) then
        Continue;
      Action := TCustomAction(Services.ActionList.Actions[Index]);
      if SameText(Action.Category, 'Atlas') then
        Continue;
      if Action.ShortCut = AShortCut then
        Exit(StripHotkey(Action.Caption));
      for Secondary := 0 to Action.SecondaryShortCuts.Count - 1 do
        if Action.SecondaryShortCuts.ShortCuts[Secondary] = AShortCut then
          Exit(StripHotkey(Action.Caption));
    end;
  Result := TAtlasKeyConflicts.OwnerOf(AShortCut, TAtlasKeyConflicts.KnownIdeKeys);
end;

class function TAtlasIdeKeys.Decide(AShortCut: Word; APriority: Boolean; const AWhat: string): Boolean;
var
  Holder, Key, Seen: string;
begin
  Holder := Owner(AShortCut);
  Result := TAtlasKeyConflicts.ShouldBind(AShortCut, Holder, APriority);
  if Result or (Holder = '') then
    Exit;
  Key := ShortCutToText(AShortCut) + '|' + Holder;
  for Seen in FReported do
    if Seen = Key then
      Exit;
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
    if Key = AShortCut then
      Exit(True);
end;

class procedure TAtlasIdeKeys.MarkReported(AShortCut: Word);
begin
  if not Reported(AShortCut) then
    FReportedKeys := FReportedKeys + [AShortCut];
end;

class procedure TAtlasIdeKeys.Bind(const ABinding: IOTAKeyboardBinding; var AIndex: Integer);
var
  Keyboard: IOTAKeyboardServices;
begin
  Unbind(AIndex);
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    AIndex := Keyboard.AddKeyboardBinding(ABinding);
end;

class procedure TAtlasIdeKeys.Unbind(var AIndex: Integer);
var
  Keyboard: IOTAKeyboardServices;
begin
  if (AIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    Keyboard.RemoveKeyboardBinding(AIndex);
  AIndex := -1;
end;

class procedure TAtlasIdeKeys.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
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
    Exit;
  for Index := 0 to Integer(Needed div SizeOf(HMODULE)) - 1 do
    if (Index <= High(Modules)) and (GetModuleFileName(Modules[Index], Name, Length(Name)) > 0) then
      Names := Names + [string(Name)];
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
      if SameText(Seen, Extension) then
        Known := True;
    if Known then
      Continue;
    FForeignReported := FForeignReported + [Extension];
    AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ForeignCompletion, [Extension]));
  end;
end;

end.
