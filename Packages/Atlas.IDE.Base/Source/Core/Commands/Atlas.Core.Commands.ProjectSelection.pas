unit Atlas.Core.Commands.ProjectSelection;

// Auswahl im Kontextmenü der Projektverwaltung (#1817), ohne VCL und Open
// Tools API. Die IDE nennt beim Aufbau des Menüs nur die Art der gewählten
// Knoten (Datei, Ordner, Projekt) und das Projekt; die Dateien selbst erst
// beim Ausführen (je Knoten eine Kennung: Datei, Ordner oder Projektdatei).
// - Resolve macht aus den Kennungen die Units der Auswahl: eine .pas bleibt,
//   eine Formulardatei (.dfm, .fmx) wird zu ihrer Unit, sofern die zum
//   Projekt gehört, ein Ordner zu den Units des Projekts darin, das Projekt zu
//   allen seinen Units. Doppelte fallen weg (ohne Rücksicht auf Groß- und
//   Kleinschreibung), die Reihenfolge der Auswahl bleibt.
// - OfKinds beschreibt die Auswahl beim Aufbau des Menüs: Kennt die IDE nur
//   die Art, gilt die Auswahl als ungeklärt (Resolved = False); ein einzelnes
//   Projekt ist schon geklärt (seine Units sind bekannt).
// - TAtlasProjectContext hält die Auswahl, solange Atlas das Menü aufbaut
//   bzw. einen Eintrag ausführt. Befehle der Module lesen sie dort (Text,
//   Sichtbarkeit, Ausführen); außerhalb ist sie leer und Active False, so
//   bleiben die Befehle des Menüs in der Befehlspalette unsichtbar.
// Nur im Hauptthread verwenden.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines gewählten Knotens: Unit (.pas), Formulardatei, andere Datei, Ordner, Projekt.</summary>
  TAtlasProjectNodeKind = (SourceFile, FormFile, OtherFile, Folder, Project);
{$SCOPEDENUMS OFF}
  TAtlasProjectNodeKinds = set of TAtlasProjectNodeKind;

  /// <summary>Auswahl in der Projektverwaltung.</summary>
  TAtlasProjectSelection = record
  private
    class function KeyOf(const AFileName: string): string; static;
    class function IsUnit(const AFileName: string): Boolean; static;
    class procedure AddUnique(var AUnits: TArray<string>; const AFileName: string); static;
    class procedure AddFolder(var AUnits: TArray<string>; const AFolder: string;
      const AProjectFiles: TArray<string>); static;
    class function FindIn(const AFileName: string; const AProjectFiles: TArray<string>;
      out AFound: string): Boolean; static;
  public
    /// <summary>Projekt der Auswahl; '' ohne.</summary>
    ProjectFile: string;
    Kinds: TAtlasProjectNodeKinds;
    /// <summary>Units der Auswahl ohne Doppelte; nur gültig, wenn Resolved.</summary>
    Units: TArray<string>;
    /// <summary>Units bekannt (beim Ausführen, bei einem einzelnen Projekt auch schon beim Aufbau).</summary>
    Resolved: Boolean;
    /// <summary>Mehrere Knoten gewählt.</summary>
    Multiple: Boolean;
    /// <summary>Kann die Auswahl Units enthalten? Geklärt: mindestens eine. Ungeklärt: eine Unit, eine
    /// Formulardatei oder ein Ordner bzw. Projekt mit Units ist gewählt.</summary>
    function HasUnits: Boolean;
    /// <summary>Genau eine Unit (geklärt) bzw. genau ein Knoten, der eine Unit sein kann (ungeklärt)?
    /// AFileName ist nur geklärt gesetzt.</summary>
    function SingleUnit(out AFileName: string): Boolean;
    /// <summary>Art einer Kennung der IDE (Datei, Ordner oder Projektdatei) nach ihrer Endung.</summary>
    class function KindOf(const AIdent: string): TAtlasProjectNodeKind; static;
    /// <summary>Units zu den Kennungen AIdents im Projekt AProjectFile mit den Dateien AProjectFiles.</summary>
    class function Resolve(const AIdents: TArray<string>; const AProjectFile: string;
      const AProjectFiles: TArray<string>): TAtlasProjectSelection; static;
    /// <summary>Zwei geklärte Auswahlen (Knoten verschiedener Projekte) zusammen: Units von ASecond hinten an, ohne
    /// Doppelte; Projekt der ersten.</summary>
    class function Merge(const AFirst, ASecond: TAtlasProjectSelection): TAtlasProjectSelection; static;
    /// <summary>Auswahl beim Aufbau des Menüs: nur die Arten AKinds; AMultiple = mehrere Knoten gewählt.</summary>
    class function OfKinds(AKinds: TAtlasProjectNodeKinds; AMultiple: Boolean; const AProjectFile: string;
      const AProjectFiles: TArray<string>): TAtlasProjectSelection; static;
  end;

  /// <summary>Auswahl, solange Atlas das Kontextmenü der Projektverwaltung aufbaut oder einen Eintrag ausführt.
  /// </summary>
  TAtlasProjectContext = record
  private class var
    FStack: TArray<TAtlasProjectSelection>;
  public
    /// <summary>Auswahl setzen; je Enter ein Leave, das die vorige Auswahl wiederherstellt.</summary>
    class procedure Enter(const ASelection: TAtlasProjectSelection); static;
    class procedure Leave; static;
    /// <summary>Wird das Menü gerade aufgebaut bzw. ein Eintrag ausgeführt?</summary>
    class function Active: Boolean; static;
    /// <summary>Aktuelle Auswahl; leer außerhalb.</summary>
    class function Current: TAtlasProjectSelection; static;
  end;

implementation

uses
  System.SysUtils;

const
  cUnitExtension = '.pas';

{ TAtlasProjectSelection }

class function TAtlasProjectSelection.KeyOf(const AFileName: string): string;
begin
  // Trennzeichen beider Systeme gleich behandeln: Die Tests laufen auch unter Linux.
  Result := AnsiUpperCase(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
end;

class function TAtlasProjectSelection.IsUnit(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), cUnitExtension);
end;

class function TAtlasProjectSelection.KindOf(const AIdent: string): TAtlasProjectNodeKind;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AIdent));
  if mExtension = cUnitExtension then
  begin
    Exit(TAtlasProjectNodeKind.SourceFile);
  end;
  if (mExtension = '.dfm') or (mExtension = '.fmx') or (mExtension = '.lfm') then
  begin
    Exit(TAtlasProjectNodeKind.FormFile);
  end;
  if (mExtension = '.dproj') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.groupproj') then
  begin
    Exit(TAtlasProjectNodeKind.Project);
  end;
  // Ordner: ohne Endung oder mit Trennzeichen am Ende.
  if (mExtension = '') or AIdent.EndsWith('\') or AIdent.EndsWith('/') then
  begin
    Exit(TAtlasProjectNodeKind.Folder);
  end;
  Result := TAtlasProjectNodeKind.OtherFile;
end;

class procedure TAtlasProjectSelection.AddUnique(var AUnits: TArray<string>; const AFileName: string);
var
  mKey, mHeld: string;
begin
  mKey := KeyOf(AFileName);
  for mHeld in AUnits do
  begin
    if KeyOf(mHeld) = mKey then
    begin
      Exit;
    end;
  end;
  AUnits := AUnits + [AFileName];
end;

class function TAtlasProjectSelection.FindIn(const AFileName: string; const AProjectFiles: TArray<string>;
  out AFound: string): Boolean;
var
  mKey, mFile: string;
begin
  mKey := KeyOf(AFileName);
  for mFile in AProjectFiles do
  begin
    if KeyOf(mFile) = mKey then
    begin
      AFound := mFile;
      Exit(True);
    end;
  end;
  AFound := '';
  Result := False;
end;

class procedure TAtlasProjectSelection.AddFolder(var AUnits: TArray<string>; const AFolder: string;
  const AProjectFiles: TArray<string>);
var
  mPrefix, mFile: string;
begin
  mPrefix := KeyOf(AFolder);
  if not mPrefix.EndsWith('\') then
  begin
    mPrefix := mPrefix + '\';
  end;
  for mFile in AProjectFiles do
  begin
    if IsUnit(mFile) and KeyOf(mFile).StartsWith(mPrefix) then
    begin
      AddUnique(AUnits, mFile);
    end;
  end;
end;

class function TAtlasProjectSelection.Resolve(const AIdents: TArray<string>; const AProjectFile: string;
  const AProjectFiles: TArray<string>): TAtlasProjectSelection;
var
  mIdent, mFile: string;
  mKind: TAtlasProjectNodeKind;
begin
  Result := Default(TAtlasProjectSelection);
  Result.ProjectFile := AProjectFile;
  Result.Resolved := True;
  Result.Multiple := Length(AIdents) > 1;
  for mIdent in AIdents do
  begin
    if mIdent = '' then
    begin
      Continue;
    end;
    mKind := KindOf(mIdent);
    Include(Result.Kinds, mKind);
    case mKind of
      TAtlasProjectNodeKind.SourceFile:
        AddUnique(Result.Units, mIdent);
      TAtlasProjectNodeKind.FormFile:
        // Nur eine Unit, die es im Projekt gibt; eine Formulardatei ohne Unit trägt nichts bei.
        if FindIn(ChangeFileExt(mIdent, cUnitExtension), AProjectFiles, mFile) then
        begin
          AddUnique(Result.Units, mFile);
        end;
      TAtlasProjectNodeKind.Folder:
        AddFolder(Result.Units, mIdent, AProjectFiles);
      TAtlasProjectNodeKind.Project:
        for mFile in AProjectFiles do
        begin
          if IsUnit(mFile) then
          begin
            AddUnique(Result.Units, mFile);
          end;
        end;
      TAtlasProjectNodeKind.OtherFile:
        // Ressourcen, Includes und Ähnliches tragen keine Unit bei.
        Continue;
    end;
  end;
end;

class function TAtlasProjectSelection.Merge(const AFirst, ASecond: TAtlasProjectSelection): TAtlasProjectSelection;
var
  mFile: string;
begin
  Result := AFirst;
  if Result.ProjectFile = '' then
  begin
    Result.ProjectFile := ASecond.ProjectFile;
  end;
  Result.Kinds := AFirst.Kinds + ASecond.Kinds;
  Result.Resolved := AFirst.Resolved and ASecond.Resolved;
  Result.Multiple := AFirst.Multiple or ASecond.Multiple or ((AFirst.Kinds <> []) and (ASecond.Kinds <> []));
  for mFile in ASecond.Units do
  begin
    AddUnique(Result.Units, mFile);
  end;
end;

class function TAtlasProjectSelection.OfKinds(AKinds: TAtlasProjectNodeKinds; AMultiple: Boolean;
  const AProjectFile: string; const AProjectFiles: TArray<string>): TAtlasProjectSelection;
begin
  if not AMultiple and (AKinds = [TAtlasProjectNodeKind.Project]) then
  begin
    Exit(Resolve([AProjectFile], AProjectFile, AProjectFiles));
  end;
  Result := Default(TAtlasProjectSelection);
  Result.ProjectFile := AProjectFile;
  Result.Kinds := AKinds;
  Result.Multiple := AMultiple;
  // Ordner und Projekte ohne eine einzige Unit im Projekt tragen nichts bei.
  if (AKinds * [TAtlasProjectNodeKind.Folder, TAtlasProjectNodeKind.Project] <> []) and
    (Length(Resolve([AProjectFile], AProjectFile, AProjectFiles).Units) = 0) then
  begin
    Result.Kinds := Result.Kinds - [TAtlasProjectNodeKind.Folder, TAtlasProjectNodeKind.Project];
  end;
end;

function TAtlasProjectSelection.HasUnits: Boolean;
begin
  if Resolved then
  begin
    Exit(Length(Units) > 0);
  end;
  Result := Kinds * [TAtlasProjectNodeKind.SourceFile, TAtlasProjectNodeKind.FormFile,
    TAtlasProjectNodeKind.Folder, TAtlasProjectNodeKind.Project] <> [];
end;

function TAtlasProjectSelection.SingleUnit(out AFileName: string): Boolean;
begin
  AFileName := '';
  if Resolved then
  begin
    Result := Length(Units) = 1;
    if Result then
    begin
      AFileName := Units[0];
    end;
    Exit;
  end;
  Result := not Multiple and
    ((Kinds = [TAtlasProjectNodeKind.SourceFile]) or (Kinds = [TAtlasProjectNodeKind.FormFile]));
end;

{ TAtlasProjectContext }

class procedure TAtlasProjectContext.Enter(const ASelection: TAtlasProjectSelection);
begin
  FStack := FStack + [ASelection];
end;

class procedure TAtlasProjectContext.Leave;
begin
  if Length(FStack) > 0 then
  begin
    SetLength(FStack, Length(FStack) - 1);
  end;
end;

class function TAtlasProjectContext.Active: Boolean;
begin
  Result := Length(FStack) > 0;
end;

class function TAtlasProjectContext.Current: TAtlasProjectSelection;
begin
  if Length(FStack) = 0 then
  begin
    Exit(Default(TAtlasProjectSelection));
  end;
  Result := FStack[High(FStack)];
end;

end.
