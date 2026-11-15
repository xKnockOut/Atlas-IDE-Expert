unit Atlas.Core.Editor.SourceFiles;

// Welche Dateien die Editorfunktionen bearbeiten, ohne Open Tools API: an der Endung, ohne Rücksicht auf
// Groß-/Kleinschreibung. Vorher prüfte jede Editor-Unit das selbst.
// - Pascal-Quelltext: Unit, Programm, Package und Include-Datei.
// - Übersetzte Quelltexte ohne Include-Dateien (Metriken und Rekursionsmarken brauchen eine ganze Unit).
// - uses gibt es nur in Units und Programmen (das Package hat contains/requires).
// - Projektdateien: Projekt, Programm, Package und Projektgruppe.

interface

type
  TAtlasSourceFiles = record
  public
    /// <summary>.pas, .dpr, .dpk oder .inc.</summary>
    class function IsPascal(const AFileName: string): Boolean; static;
    /// <summary>.pas, .dpr oder .dpk (ohne Include-Dateien).</summary>
    class function IsCompiled(const AFileName: string): Boolean; static;
    /// <summary>.pas oder .dpr: Datei mit uses-Abschnitt.</summary>
    class function HasUses(const AFileName: string): Boolean; static;
    /// <summary>.dproj, .dpr, .dpk oder .groupproj.</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TAtlasSourceFiles }

class function TAtlasSourceFiles.IsPascal(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc']);
end;

class function TAtlasSourceFiles.IsCompiled(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk']);
end;

class function TAtlasSourceFiles.HasUses(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr']);
end;

class function TAtlasSourceFiles.IsProjectFile(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.dproj', '.dpr', '.dpk', '.groupproj']);
end;

end.
