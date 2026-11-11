unit Atlas.Core.Generate.Gallery;

// Assistenten der Kategorie „Atlas“ in Datei › Neu › Weitere (#1821), ohne VCL
// und Open Tools API. Module bieten sie als Menüeintrag mit
// TAtlasMenuPlace.Gallery an: CommandId nennt einen Befehl des Moduls, eine
// gesetzte Caption ersetzt dessen Text, die Beschreibung des Befehls steht
// unter dem Assistenten. Items macht daraus die Liste für die Galerie
// (Trennlinien, Einträge ohne Befehl und Doppelte fallen weg); Same sagt, ob
// sich die Liste geändert hat, damit die IDE-Schicht die Assistenten nur dann
// neu anmeldet. Die IDE kennt einen Assistenten an WizardId; beim Ausführen
// sucht die IDE-Schicht den Befehl über CommandIdOf neu (Regel 3).

interface

uses
  Atlas.Core.Modules.Contract;

type
  /// <summary>Ein Assistent der Galerie: Befehl, Name und Beschreibung.</summary>
  TAtlasGalleryItem = record
    CommandId: string;
    Caption: string;
    Comment: string;
  end;

  TAtlasGallery = class
  public const
    /// <summary>Kennung der Kategorie „Atlas“ in der Objektgalerie.</summary>
    cCategoryId = 'Atlas.Gallery';
    /// <summary>Name der Kategorie und Autor der Assistenten.</summary>
    cCategoryName = 'Atlas';
    /// <summary>Vorsilbe der Kennung eines Assistenten vor der Id des Befehls.</summary>
    cWizardPrefix = 'Atlas.Gallery.';
  public
    /// <summary>Assistenten aus den Einträgen AEntries (nur TAtlasMenuPlace.Gallery) mit den Befehlen ACommands, in
    /// Reihenfolge der Einträge; ohne Trennlinien, Einträge ohne Befehl und Doppelte.</summary>
    class function Items(const AEntries: TArray<TAtlasMenuEntry>;
      const ACommands: TArray<TAtlasModuleCommand>): TArray<TAtlasGalleryItem>; static;
    /// <summary>Gleiche Assistenten in gleicher Reihenfolge mit gleichen Texten?</summary>
    class function Same(const AFirst, ASecond: TArray<TAtlasGalleryItem>): Boolean; static;
    /// <summary>Kennung des Assistenten zum Befehl ACommandId.</summary>
    class function WizardId(const ACommandId: string): string; static;
    /// <summary>Befehl zur Kennung AWizardId; '' ohne die Vorsilbe.</summary>
    class function CommandIdOf(const AWizardId: string): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cSeparator = '-';

function FindCommand(const ACommands: TArray<TAtlasModuleCommand>; const AId: string;
  out ACommand: TAtlasModuleCommand): Boolean;
var
  mCommand: TAtlasModuleCommand;
begin
  for mCommand in ACommands do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      ACommand := mCommand;
      Exit(True);
    end;
  end;
  ACommand := Default(TAtlasModuleCommand);
  Result := False;
end;

function Listed(const AItems: TArray<TAtlasGalleryItem>; const ACommandId: string): Boolean;
var
  mItem: TAtlasGalleryItem;
begin
  for mItem in AItems do
  begin
    if SameText(mItem.CommandId, ACommandId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasGallery.Items(const AEntries: TArray<TAtlasMenuEntry>;
  const ACommands: TArray<TAtlasModuleCommand>): TArray<TAtlasGalleryItem>;
var
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
  mItem: TAtlasGalleryItem;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if (mEntry.Place <> TAtlasMenuPlace.Gallery) or (mEntry.CommandId = cSeparator) or
      Listed(Result, mEntry.CommandId) or not FindCommand(ACommands, mEntry.CommandId, mCommand) then
    begin
      Continue;
    end;
    mItem.CommandId := mCommand.Id;
    mItem.Caption := mEntry.Caption;
    if mItem.Caption = '' then
    begin
      mItem.Caption := mCommand.Caption;
    end;
    mItem.Comment := mCommand.Description;
    Result := Result + [mItem];
  end;
end;

class function TAtlasGallery.Same(const AFirst, ASecond: TArray<TAtlasGalleryItem>): Boolean;
var
  mIndex: Integer;
begin
  if Length(AFirst) <> Length(ASecond) then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(AFirst) do
  begin
    if (AFirst[mIndex].CommandId <> ASecond[mIndex].CommandId) or (AFirst[mIndex].Caption <> ASecond[mIndex].Caption)
      or (AFirst[mIndex].Comment <> ASecond[mIndex].Comment) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TAtlasGallery.WizardId(const ACommandId: string): string;
begin
  Result := cWizardPrefix + ACommandId;
end;

class function TAtlasGallery.CommandIdOf(const AWizardId: string): string;
begin
  Result := '';
  if AWizardId.StartsWith(cWizardPrefix, True) then
  begin
    Result := Copy(AWizardId, Length(cWizardPrefix) + 1, MaxInt);
  end;
end;

end.
