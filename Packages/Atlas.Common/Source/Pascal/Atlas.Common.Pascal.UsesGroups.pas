unit Atlas.Common.Pascal.UsesGroups;

// Gruppen der uses nach Herkunft der Unit (#2794), in dieser Reihenfolge:
//
//   System              RTL der Installation (System, Winapi, Posix, ...)
//   Delphi-Komponenten  übrige Units der Installation (Indy, FireDAC, DataSnap, Data, Xml, Soap, REST, ...)
//   VCL/FMX             Namespace Vcl oder FMX
//   Bibliothek          Bibliothekspfad der IDE außerhalb der Installation (Spring, DUnitX, mORMot, ...)
//   Packages            andere Projekte der Projektgruppe
//   Projekt             eigenes Projekt und sein Suchpfad
//
// Der Host kennt den Fundort der Unit (TUsesUnitFile); ohne Fundort entscheidet der Namespace, unbekannte
// Units zählen zum Projekt. Über jeder Gruppe steht je nach Darstellung ein Kommentar wie { System }; solche
// Kommentare erkennt IsLabel in beiden Sprachen, damit ein erneutes Sortieren sie ersetzt statt verdoppelt.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  TUsesGroups = class
  public
    /// <summary>Gruppe nur aus dem Namen (Namespace); Units ohne bekannten Namespace zählen zum Projekt.</summary>
    class function OfName(const AUnitName: string): TUsesGroup; static;
    /// <summary>Gruppe aus dem Fundort; bei unbekanntem Fundort wie OfName.</summary>
    class function OfFile(const AUnitName: string; const AFile: TUsesUnitFile): TUsesGroup; static;
    /// <summary>Kommentartext der Gruppe in der aktuellen Sprache, z. B. "{ System }".</summary>
    class function LabelOf(AGroup: TUsesGroup): string; static;
    /// <summary>Ist AComment ein Gruppenkommentar ({ … } oder (* … *)) in einer der beiden Sprachen?</summary>
    class function IsLabel(const AComment: string): Boolean; static;
    /// <summary>Darstellung aus dem Einstellungswert: "lines", sonst Comments.</summary>
    class function StyleOf(const AValue: string): TUsesGroupStyle; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Localization.Texts;

const
  cGroupTexts: array[TUsesGroup] of TAtlasText = (
    (De: 'System'; En: 'System'),
    (De: 'Delphi-Komponenten'; En: 'Delphi components'),
    (De: 'VCL/FMX'; En: 'VCL/FMX'),
    (De: 'Bibliothek'; En: 'Library'),
    (De: 'Packages'; En: 'Packages'),
    (De: 'Projekt'; En: 'Project'));

  cRuntimeNamespaces: array[0..5] of string = ('System', 'Winapi', 'Posix', 'Macapi', 'Androidapi', 'iOSapi');
  cFrameworkNamespaces: array[0..1] of string = ('Vcl', 'FMX');
  cComponentNamespaces: array[0..8] of string = ('Data', 'Datasnap', 'FireDAC', 'Xml', 'Soap', 'Web', 'REST', 'IBX',
    'Bde');

/// <summary>Teil vor dem ersten Punkt; '' ohne Punkt.</summary>
function NamespaceOf(const AUnitName: string): string;
var
  mDot: Integer;
begin
  mDot := Pos('.', AUnitName);
  Result := '';
  if mDot > 0 then
  begin
    Result := Copy(AUnitName, 1, mDot - 1);
  end;
end;

/// <summary>Indy ohne Namespace: Id gefolgt von einem Großbuchstaben (IdHTTP, IdGlobal).</summary>
function IsIndyName(const AUnitName: string): Boolean;
begin
  Result := (Length(AUnitName) > 2) and StartsStr('Id', AUnitName) and CharInSet(AUnitName[3], ['A'..'Z']) and
    (Pos('.', AUnitName) = 0);
end;

class function TUsesGroups.OfName(const AUnitName: string): TUsesGroup;
var
  mNamespace: string;
begin
  mNamespace := NamespaceOf(AUnitName);
  if MatchText(mNamespace, cFrameworkNamespaces) then
  begin
    Result := TUsesGroup.Framework;
  end
  else if MatchText(mNamespace, cRuntimeNamespaces) then
  begin
    Result := TUsesGroup.RuntimeLibrary;
  end
  else if MatchText(mNamespace, cComponentNamespaces) or IsIndyName(AUnitName) then
  begin
    Result := TUsesGroup.DelphiComponents;
  end
  else
  begin
    Result := TUsesGroup.Project;
  end;
end;

/// <summary>Gruppe einer Unit der Installation: VCL/FMX nach Namespace oder Ordner, RTL aus source\rtl,
/// alles andere (Indy, FireDAC, DataSnap, Xml …) als Delphi-Komponenten.</summary>
function InstallationGroup(const AUnitName, AInstallPath: string): TUsesGroup;
var
  mPath: string;
begin
  mPath := LowerCase(AInstallPath.Replace('/', '\'));
  if MatchText(NamespaceOf(AUnitName), cFrameworkNamespaces) or StartsStr('source\vcl\', mPath) or
    StartsStr('source\fmx\', mPath) then
  begin
    Result := TUsesGroup.Framework;
  end
  else if MatchText(NamespaceOf(AUnitName), cRuntimeNamespaces) or StartsStr('source\rtl\', mPath) then
  begin
    Result := TUsesGroup.RuntimeLibrary;
  end
  else
  begin
    Result := TUsesGroup.DelphiComponents;
  end;
end;

class function TUsesGroups.OfFile(const AUnitName: string; const AFile: TUsesUnitFile): TUsesGroup;
begin
  case AFile.Origin of
    TUsesFileOrigin.Installation:
      Result := InstallationGroup(AUnitName, AFile.InstallPath);
    TUsesFileOrigin.LibraryPath:
      Result := TUsesGroup.LibraryPath;
    TUsesFileOrigin.ProjectGroup:
      Result := TUsesGroup.ProjectGroup;
    TUsesFileOrigin.OwnProject:
      Result := TUsesGroup.Project;
  else
    Result := OfName(AUnitName);
  end;
end;

class function TUsesGroups.LabelOf(AGroup: TUsesGroup): string;
begin
  Result := '{ ' + cGroupTexts[AGroup].Text + ' }';
end;

/// <summary>Inhalt des Kommentars ohne Klammern und Leerraum; '' bei anderem Text.</summary>
function CommentBody(const AComment: string): string;
var
  mText: string;
begin
  mText := Trim(AComment);
  Result := '';
  if StartsStr('{', mText) and EndsStr('}', mText) then
  begin
    Result := Trim(Copy(mText, 2, Length(mText) - 2));
  end
  else if StartsStr('(*', mText) and EndsStr('*)', mText) and (Length(mText) >= 4) then
  begin
    Result := Trim(Copy(mText, 3, Length(mText) - 4));
  end;
end;

class function TUsesGroups.IsLabel(const AComment: string): Boolean;
var
  mBody: string;
  mGroup: TUsesGroup;
begin
  mBody := CommentBody(AComment);
  Result := False;
  if mBody = '' then
  begin
    Exit;
  end;
  for mGroup := Low(TUsesGroup) to High(TUsesGroup) do
  begin
    if SameText(mBody, cGroupTexts[mGroup].De) or SameText(mBody, cGroupTexts[mGroup].En) then
    begin
      Exit(True);
    end;
  end;
end;

class function TUsesGroups.StyleOf(const AValue: string): TUsesGroupStyle;
begin
  Result := TUsesGroupStyle.Comments;
  if SameText(AValue, 'lines') then
  begin
    Result := TUsesGroupStyle.Lines;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.UsesGroups', cGroupTexts);

end.
