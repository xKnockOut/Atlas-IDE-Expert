unit Atlas.Core.Vcs.Internals.SvnParser;

// Liest die Ausgaben von svn für die Versionsverwaltung (#571, Weg aus #276).
// Alle Aufrufe mit --xml: Die Ausgabe ist dann UTF-8, unabhängig von Sprache
// und Codepage der Konsole.
//   svn info --xml        Wurzel der Arbeitskopie, Pfad im Repository, Revision
//   svn status --xml      geänderte, neue und unversionierte Dateien
//   svn blame --xml       Zeilenherkunft
// Der Branch ist der Pfad im Repository: "^/trunk" wird "trunk",
// "^/projekt/branches/x/src" wird "branches/x"; ohne übliche Ablage
// (trunk, branches, tags) der ganze Pfad ohne "^/".

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasSvnInfo = record
    /// <summary>Wurzel der Arbeitskopie (wcroot-abspath).</summary>
    Root: string;
    /// <summary>Pfad im Repository ohne "^/", z. B. "projekt/branches/x".</summary>
    RelativeUrl: string;
    /// <summary>Revision der Arbeitskopie.</summary>
    Revision: string;
  end;

  TAtlasSvnParser = class
  public
    /// <summary>Ausgabe von "svn info --xml" (erster Eintrag).</summary>
    class function ParseInfo(const AText: string): TAtlasSvnInfo; static;
    /// <summary>Branch aus dem Pfad im Repository (siehe Kopf der Unit).</summary>
    class function BranchOf(const ARelativeUrl: string): string; static;
    /// <summary>Ausgabe von "svn status --xml"; relative Pfade gelten unter ARoot. Unveränderte, ignorierte
    /// und externe Einträge entfallen.</summary>
    class function ParseStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>; static;
    /// <summary>Ausgabe von "svn blame --xml".</summary>
    class function ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>; static;
    /// <summary>Art aus wc-status item und props; False für Einträge ohne Änderung.</summary>
    class function KindOf(const AItem, AProps: string; out AKind: TAtlasVcsChangeKind): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text;

class function TAtlasSvnParser.ParseInfo(const AText: string): TAtlasSvnInfo;
var
  Reader: TAtlasVcsXmlReader;
  Element: string;
  Depth: Integer;
  Url, RepositoryRoot: string;
begin
  Result.Root := '';
  Result.RelativeUrl := '';
  Result.Revision := '';
  Url := '';
  RepositoryRoot := '';
  Element := '';
  Depth := 0;
  Reader := TAtlasVcsXmlReader.Create(AText);
  try
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          begin
            if Reader.Name = 'entry' then
            begin
              Inc(Depth);
              // Nur der erste Eintrag zählt.
              if Depth = 1 then
                Result.Revision := Reader.Attr('revision');
            end;
            if not Reader.EmptyElement then
              Element := Reader.Name;
          end;
        TAtlasVcsXmlNode.EndTag:
          begin
            Element := '';
            if Reader.Name = 'entry' then
              Break;
          end;
        TAtlasVcsXmlNode.Text:
          if Element = 'wcroot-abspath' then
            Result.Root := VcsNormalizeDir(Reader.Value)
          else if Element = 'relative-url' then
            Result.RelativeUrl := Trim(Reader.Value)
          else if Element = 'url' then
            Url := Trim(Reader.Value)
          else if Element = 'root' then
            RepositoryRoot := Trim(Reader.Value);
      end;
  finally
    Reader.Free;
  end;
  if Depth = 0 then
    raise EAtlasVcsParse.Create('svn info: kein Eintrag');
  // svn vor 1.8 kennt relative-url nicht: aus url und root bilden.
  if (Result.RelativeUrl = '') and (RepositoryRoot <> '') and (Copy(Url, 1, Length(RepositoryRoot)) = RepositoryRoot) then
    Result.RelativeUrl := '^' + Copy(Url, Length(RepositoryRoot) + 1, MaxInt);
  if Copy(Result.RelativeUrl, 1, 1) = '^' then
    Delete(Result.RelativeUrl, 1, 1);
  while Copy(Result.RelativeUrl, 1, 1) = '/' do
    Delete(Result.RelativeUrl, 1, 1);
end;

class function TAtlasSvnParser.BranchOf(const ARelativeUrl: string): string;
var
  Parts: TArray<string>;
  Index: Integer;
  Part: string;
begin
  Parts := ARelativeUrl.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Parts) do
  begin
    Part := LowerCase(Parts[Index]);
    if Part = 'trunk' then
      Exit(Parts[Index]);
    if ((Part = 'branches') or (Part = 'tags')) and (Index < High(Parts)) then
      Exit(Parts[Index] + '/' + Parts[Index + 1]);
  end;
  Result := string.Join('/', Parts);
end;

class function TAtlasSvnParser.KindOf(const AItem, AProps: string; out AKind: TAtlasVcsChangeKind): Boolean;
begin
  Result := True;
  if AItem = 'modified' then
    AKind := TAtlasVcsChangeKind.Modified
  else if AItem = 'added' then
    AKind := TAtlasVcsChangeKind.Added
  else if AItem = 'deleted' then
    AKind := TAtlasVcsChangeKind.Deleted
  else if AItem = 'replaced' then
    AKind := TAtlasVcsChangeKind.Replaced
  else if AItem = 'unversioned' then
    AKind := TAtlasVcsChangeKind.Untracked
  else if (AItem = 'conflicted') or (AProps = 'conflicted') then
    AKind := TAtlasVcsChangeKind.Conflicted
  else if (AItem = 'missing') or (AItem = 'incomplete') then
    AKind := TAtlasVcsChangeKind.Missing
  else if AItem = 'obstructed' then
    AKind := TAtlasVcsChangeKind.TypeChanged
  else if AItem = 'merged' then
    AKind := TAtlasVcsChangeKind.Modified
  else if AProps = 'modified' then
    // Nur Eigenschaften geändert (svn:eol-style und ähnliche).
    AKind := TAtlasVcsChangeKind.Modified
  else
  begin
    // normal, none, ignored, external
    AKind := TAtlasVcsChangeKind.Modified;
    Result := False;
  end;
end;

class function TAtlasSvnParser.ParseStatus(const AText, ARoot: string): TArray<TAtlasVcsChange>;
var
  Reader: TAtlasVcsXmlReader;
  Path, Item, Props: string;
  Change: TAtlasVcsChange;
  Kind: TAtlasVcsChangeKind;
  InEntry: Boolean;
begin
  Result := nil;
  InEntry := False;
  Path := '';
  Reader := TAtlasVcsXmlReader.Create(AText);
  try
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          if Reader.Name = 'entry' then
          begin
            InEntry := True;
            Path := Reader.Attr('path');
          end
          else if (Reader.Name = 'wc-status') and InEntry then
          begin
            Item := Reader.Attr('item');
            Props := Reader.Attr('props');
            if KindOf(Item, Props, Kind) and (Path <> '') then
            begin
              // Absolute Pfade (bei absolutem Ziel) bleiben, relative gelten unter der Wurzel.
              if (Pos(':', Path) = 2) or (Copy(Path, 1, 1) = '/') or (Copy(Path, 1, 2) = '\\') then
                Change.Path := VcsNormalizeDir(Path)
              else
                Change.Path := VcsFullPath(ARoot, Path);
              Change.OldPath := '';
              Change.Kind := Kind;
              Change.Staged := False;
              Change.Unstaged := True;
              Result := Result + [Change];
            end;
            // Nur der erste wc-status je Eintrag; repos-status (mit --show-updates) folgt getrennt.
            InEntry := False;
          end;
        TAtlasVcsXmlNode.EndTag:
          if Reader.Name = 'entry' then
            InEntry := False;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    Reader.Free;
  end;
end;

class function TAtlasSvnParser.ParseBlame(const AText: string): TArray<TAtlasVcsBlameLine>;
var
  Reader: TAtlasVcsXmlReader;
  Item: TAtlasVcsBlameLine;
  InEntry, InMerged: Boolean;
  Element: string;
  Number: Integer;
  Date: TDateTime;
begin
  Result := nil;
  InEntry := False;
  InMerged := False;
  Element := '';
  Item := Default(TAtlasVcsBlameLine);
  Reader := TAtlasVcsXmlReader.Create(AText);
  try
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          if Reader.Name = 'entry' then
          begin
            Item := Default(TAtlasVcsBlameLine);
            if not TryStrToInt(Reader.Attr('line-number'), Number) then
              raise EAtlasVcsParse.Create('svn blame: line-number fehlt');
            Item.Line := Number;
            InEntry := True;
            if Reader.EmptyElement then
            begin
              Result := Result + [Item];
              InEntry := False;
            end;
          end
          else if Reader.Name = 'merged' then
            InMerged := not Reader.EmptyElement
          else if (Reader.Name = 'commit') and InEntry and not InMerged then
            Item.Revision := Reader.Attr('revision')
          else if not Reader.EmptyElement then
            Element := Reader.Name;
        TAtlasVcsXmlNode.EndTag:
          begin
            Element := '';
            if Reader.Name = 'merged' then
              InMerged := False
            else if (Reader.Name = 'entry') and InEntry then
            begin
              Result := Result + [Item];
              InEntry := False;
            end;
          end;
        TAtlasVcsXmlNode.Text:
          if InEntry and not InMerged then
            if Element = 'author' then
              Item.Author := Reader.Value
            else if (Element = 'date') and VcsParseIsoDate(Reader.Value, Date) then
              Item.Date := Date;
      end;
  finally
    Reader.Free;
  end;
end;

end.
