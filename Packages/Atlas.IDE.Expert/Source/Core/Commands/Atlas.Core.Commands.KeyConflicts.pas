unit Atlas.Core.Commands.KeyConflicts;

// Verträglichkeit mit anderen Erweiterungen (#494), Teil ohne Open Tools API:
// - Tastenkürzel von Atlas gegen bekannte Belegungen prüfen (Aktionen der IDE
//   und anderer Erweiterungen, Editor-Belegungen der Standard-Tastaturbelegung).
//   Bei Konflikt belegt Atlas die Taste nur mit ausdrücklichem Vorrang; sonst
//   bleibt die fremde Belegung aktiv.
// - Erweiterungen mit eigener Vervollständigung an ihren Packages erkennen;
//   Atlas weist nur darauf hin und schaltet fremde Erweiterungen nie ab.
// - Seite „Tastenkonflikte“: je Atlas-Taste (Befehlspalette, Syntaxprüfung,
//   Vervollständigung, Parameter-Hint) Taste, fremde Belegung und die Wahl
//   „Atlas verwenden“, „anderer Belegung überlassen“ oder „andere Taste für
//   Atlas“ (TAtlasKeyEntry).
// Kürzel sind TShortCut-Werte (Word) wie in Vcl.Menus.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin;

type
  {$SCOPEDENUMS ON}
  TAtlasKeyFunction = (Palette, Check, Completion, Signature);
  TAtlasKeyChoice = (UseAtlas, LeaveOther, OtherKey);
  /// <summary>NoKey: keine Taste; IdeKey: Taste der IDE über Code Insight, Atlas belegt nichts selbst;
  /// Free: Atlas belegt die freie Taste; AtlasWins: belegt, Atlas hat Vorrang; Left: belegt, Atlas
  /// überlässt sie der anderen Belegung.</summary>
  TAtlasKeyStatus = (NoKey, IdeKey, Free, AtlasWins, Left);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Taste von Atlas auf der Seite „Tastenkonflikte“ (#494).</summary>
  TAtlasKeyEntry = record
    Func: TAtlasKeyFunction;
    /// <summary>0 = keine Taste; bei Vervollständigung und Parameter-Hint die Taste der IDE.</summary>
    Key: Word;
    Priority: Boolean;
    class function Create(AFunc: TAtlasKeyFunction; AKey: Word; APriority: Boolean): TAtlasKeyEntry; static;
    /// <summary>Alle Atlas-Tasten aus den Einstellungen, in fester Reihenfolge.</summary>
    class function FromSettings(const ASettings: TAtlasPluginSettings): TArray<TAtlasKeyEntry>; static;
    /// <summary>Tasten und Vorrang zurück in die Einstellungen.</summary>
    class procedure ToSettings(const AEntries: TArray<TAtlasKeyEntry>; var ASettings: TAtlasPluginSettings); static;
    /// <summary>Taste der IDE, über die Code Insight Atlas aufruft (Strg+Leer, Strg+Umschalt+Leer); sonst 0.</summary>
    function IdeKey: Word;
    function Choice: TAtlasKeyChoice;
    /// <summary>Wahl übernehmen: Atlas verwenden = Vorrang; sonst ohne Vorrang. Atlas verwenden ohne eigene
    /// Taste bei Vervollständigung und Parameter-Hint: Atlas belegt die Taste der IDE selbst.</summary>
    procedure Choose(AChoice: TAtlasKeyChoice);
    /// <summary>Zustand bei fremder Belegung AOwner ('' = frei).</summary>
    function Status(const AOwner: string): TAtlasKeyStatus;
  end;

  TAtlasKeyOwner = record
    ShortCut: Word;
    Owner: string;
    class function Create(AShortCut: Word; const AOwner: string): TAtlasKeyOwner; static;
  end;

  TAtlasKeyConflicts = class
  public const
    scShift = $2000;
    scCtrl = $4000;
    scAlt = $8000;
    PaletteDefault = scCtrl or scShift or Ord('P');
    CheckDefault = scCtrl or scAlt or $78; // VK_F9
    IdeCompletionKey = scCtrl or $20; // Strg+Leer
    IdeSignatureKey = scCtrl or scShift or $20; // Strg+Umschalt+Leer
  public
    /// <summary>Editor-Belegungen der Standard-Tastaturbelegung, die keine Aktionen sind.</summary>
    class function KnownIdeKeys: TArray<TAtlasKeyOwner>; static;
    /// <summary>Wer belegt AShortCut schon? '' wenn frei.</summary>
    class function OwnerOf(AShortCut: Word; const AKeys: TArray<TAtlasKeyOwner>): string; static;
    /// <summary>Soll Atlas die Taste belegen? Nur frei oder mit Vorrang; 0 heißt „keine Taste“.</summary>
    class function ShouldBind(AShortCut: Word; const AOwner: string; APriority: Boolean): Boolean; static;
    /// <summary>Namen von Erweiterungen mit eigener Vervollständigung unter den geladenen Modulen.</summary>
    class function CompletionExtensions(const AModules: TArray<string>): TArray<string>; static;
  end;

implementation

{ TAtlasKeyEntry }

class function TAtlasKeyEntry.Create(AFunc: TAtlasKeyFunction; AKey: Word; APriority: Boolean): TAtlasKeyEntry;
begin
  Result.Func := AFunc;
  Result.Key := AKey;
  Result.Priority := APriority;
end;

class function TAtlasKeyEntry.FromSettings(const ASettings: TAtlasPluginSettings): TArray<TAtlasKeyEntry>;
begin
  Result := [Create(TAtlasKeyFunction.Palette, Word(ASettings.PaletteKey), ASettings.PaletteKeyPriority),
    Create(TAtlasKeyFunction.Check, Word(ASettings.CheckKey), ASettings.CheckKeyPriority),
    Create(TAtlasKeyFunction.Completion, Word(ASettings.CompletionKey), ASettings.CompletionKeyPriority),
    Create(TAtlasKeyFunction.Signature, Word(ASettings.SignatureKey), ASettings.SignatureKeyPriority)];
end;

class procedure TAtlasKeyEntry.ToSettings(const AEntries: TArray<TAtlasKeyEntry>;
  var ASettings: TAtlasPluginSettings);
var
  Entry: TAtlasKeyEntry;
begin
  for Entry in AEntries do
    case Entry.Func of
      TAtlasKeyFunction.Palette:
        begin
          ASettings.PaletteKey := Entry.Key;
          ASettings.PaletteKeyPriority := Entry.Priority;
        end;
      TAtlasKeyFunction.Check:
        begin
          ASettings.CheckKey := Entry.Key;
          ASettings.CheckKeyPriority := Entry.Priority;
        end;
      TAtlasKeyFunction.Completion:
        begin
          ASettings.CompletionKey := Entry.Key;
          ASettings.CompletionKeyPriority := Entry.Priority;
        end;
      TAtlasKeyFunction.Signature:
        begin
          ASettings.SignatureKey := Entry.Key;
          ASettings.SignatureKeyPriority := Entry.Priority;
        end;
    end;
end;

function TAtlasKeyEntry.IdeKey: Word;
begin
  case Func of
    TAtlasKeyFunction.Completion:
      Result := TAtlasKeyConflicts.IdeCompletionKey;
    TAtlasKeyFunction.Signature:
      Result := TAtlasKeyConflicts.IdeSignatureKey;
  else
    Result := 0;
  end;
end;

function TAtlasKeyEntry.Choice: TAtlasKeyChoice;
begin
  if Priority then
    Result := TAtlasKeyChoice.UseAtlas
  else
    Result := TAtlasKeyChoice.LeaveOther;
end;

procedure TAtlasKeyEntry.Choose(AChoice: TAtlasKeyChoice);
begin
  Priority := AChoice = TAtlasKeyChoice.UseAtlas;
  if Priority and (Key = 0) then
    Key := IdeKey;
end;

function TAtlasKeyEntry.Status(const AOwner: string): TAtlasKeyStatus;
begin
  if Key = 0 then
  begin
    if IdeKey <> 0 then
      Result := TAtlasKeyStatus.IdeKey
    else
      Result := TAtlasKeyStatus.NoKey;
  end
  else if AOwner = '' then
    Result := TAtlasKeyStatus.Free
  else if Priority then
    Result := TAtlasKeyStatus.AtlasWins
  else
    Result := TAtlasKeyStatus.Left;
end;

{ TAtlasKeyOwner }

class function TAtlasKeyOwner.Create(AShortCut: Word; const AOwner: string): TAtlasKeyOwner;
begin
  Result.ShortCut := AShortCut;
  Result.Owner := AOwner;
end;

{ TAtlasKeyConflicts }

class function TAtlasKeyConflicts.KnownIdeKeys: TArray<TAtlasKeyOwner>;
begin
  Result := [TAtlasKeyOwner.Create(scCtrl or scShift or Ord('P'), 'IDE: Tastaturmakro abspielen'),
    TAtlasKeyOwner.Create(scCtrl or scShift or Ord('R'), 'IDE: Tastaturmakro aufzeichnen')];
end;

class function TAtlasKeyConflicts.OwnerOf(AShortCut: Word; const AKeys: TArray<TAtlasKeyOwner>): string;
var
  Key: TAtlasKeyOwner;
begin
  Result := '';
  if AShortCut = 0 then
    Exit;
  for Key in AKeys do
    if Key.ShortCut = AShortCut then
      Exit(Key.Owner);
end;

class function TAtlasKeyConflicts.ShouldBind(AShortCut: Word; const AOwner: string; APriority: Boolean): Boolean;
begin
  Result := (AShortCut <> 0) and ((AOwner = '') or APriority);
end;

class function TAtlasKeyConflicts.CompletionExtensions(const AModules: TArray<string>): TArray<string>;
type
  TKnown = record
    Prefix: string;
    Name: string;
  end;
const
  // Package-Namen (ohne Version) und Anzeigename; nur Erweiterungen mit eigener Vervollständigung.
  Known: array[0..2] of TKnown = (
    (Prefix: 'CnWizards'; Name: 'CnPack (Input Helper)'),
    (Prefix: 'Castalia'; Name: 'Castalia'),
    (Prefix: 'CodeInsightPlus'; Name: 'Code Insight Plus'));
var
  Module, Name: string;
  Index: Integer;
  Found: Boolean;
begin
  Result := nil;
  for Index := Low(Known) to High(Known) do
  begin
    Found := False;
    for Module in AModules do
    begin
      Name := ExtractFileName(Module);
      if Name.StartsWith(Known[Index].Prefix, True) then
        Found := True;
    end;
    if Found then
      Result := Result + [Known[Index].Name];
  end;
end;

end.
