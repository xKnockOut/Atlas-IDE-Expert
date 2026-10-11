unit Atlas.Core.Commands.KeyConflicts;

// Verträglichkeit mit anderen Erweiterungen (#494), Teil ohne Open Tools API:
// - Tastenkürzel von Atlas gegen bekannte Belegungen prüfen (Aktionen der IDE
//   und anderer Erweiterungen, Editor-Belegungen der Standard-Tastaturbelegung).
//   Bei Konflikt belegt Atlas die Taste nur mit ausdrücklichem Vorrang; sonst
//   bleibt die fremde Belegung aktiv.
// - Erweiterungen mit eigener Vervollständigung an ihren Packages erkennen;
//   Atlas weist nur darauf hin und schaltet fremde Erweiterungen nie ab.
// Kürzel sind TShortCut-Werte (Word) wie in Vcl.Menus.

interface

uses
  System.SysUtils;

type
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
