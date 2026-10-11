unit Atlas.IDE.Commands.Keys;

// Tastenkürzel von Atlas in der IDE (#494): vor dem Belegen prüfen, ob die
// IDE oder eine andere Erweiterung die Taste schon nutzt (Aktionen aus
// INTAServices.ActionList, bekannte Editor-Belegungen). Ohne Vorrang bleibt die
// fremde Belegung aktiv und Atlas meldet den Konflikt in der Meldungsansicht.
// Beim Start außerdem Hinweis auf Erweiterungen mit eigener Vervollständigung.

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  TAtlasIdeKeys = class
  private class var
    FReported: TArray<string>;
  public
    /// <summary>Wer belegt AShortCut außer Atlas? '' wenn frei.</summary>
    class function Owner(AShortCut: Word): string; static;
    /// <summary>Soll Atlas AShortCut für AWhat belegen? Meldet einen Konflikt einmal je Taste und Besitzer.</summary>
    class function Decide(AShortCut: Word; APriority: Boolean; const AWhat: string): Boolean; static;
    /// <summary>ABinding (neu) anmelden bzw. abmelden; AIndex -1 = nicht angemeldet.</summary>
    class procedure Bind(const ABinding: IOTAKeyboardBinding; var AIndex: Integer); static;
    class procedure Unbind(var AIndex: Integer); static;
    /// <summary>Hinweis, wenn eine andere Erweiterung eine eigene Vervollständigung mitbringt.</summary>
    class procedure ReportForeignCompletion; static;
    class procedure AddMessage(const AText: string); static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.PsAPI,
  System.Classes,
  Vcl.ActnList,
  Vcl.Menus,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.UI.Strings;

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

class procedure TAtlasIdeKeys.ReportForeignCompletion;
var
  Modules: array[0..1023] of HMODULE;
  Needed: DWORD;
  Index: Integer;
  Names: TArray<string>;
  Name: array[0..MAX_PATH] of Char;
  Extension: string;
begin
  Names := nil;
  if not EnumProcessModules(GetCurrentProcess, @Modules[0], SizeOf(Modules), Needed) then
    Exit;
  for Index := 0 to Integer(Needed div SizeOf(HMODULE)) - 1 do
    if (Index <= High(Modules)) and (GetModuleFileName(Modules[Index], Name, Length(Name)) > 0) then
      Names := Names + [string(Name)];
  for Extension in TAtlasKeyConflicts.CompletionExtensions(Names) do
    AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ForeignCompletion, [Extension]));
end;

end.
