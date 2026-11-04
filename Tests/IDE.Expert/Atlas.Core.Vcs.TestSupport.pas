unit Atlas.Core.Vcs.TestSupport;

// Gemeinsame Hilfen der Tests der Versionsverwaltung: aufgezeichnete Ausgaben von git und svn und Pfade.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

const
  Hash1 = '1979e3d795214220705682d5b0b63c8f3b7e66d7';
  Hash2 = '35b70b0b58543816b60892fa1b872449fdc3886b';
  // Aufgezeichnet mit git 2.43: log --all --fixed-strings --regexp-ignore-case --grep=atl-12
  // --format=%x1e%H%x00%ct%x00%an%x00%B --name-status -z --no-renames (neuester zuerst).
  GitHistorySample =
    #$1E'28358feaf94440dbfe2fcc3aa2cb742e2d972f37'#0'1761603600'#0'Marco B'#0'ATL-12: weiter'#10#0#10 +
    'M'#0'A.pas'#0'A'#0'Neu.pas'#0'D'#0'src/B.pas'#0 +
    #$1E'7637c6cf53522335c876c98aef9a32861d4dc147'#0'1761600000'#0'Marco B'#0'ATL-12 Erster Stand'#10#10 +
    'Zweite Zeile'#10#0#10'A'#0'A.pas'#0'A'#0'src/B.pas'#0;

/// <summary>Wurzel der Arbeitskopie für die Plattform.</summary>
function Root: string;

/// <summary>Voller Pfad zu ARelative unter Root.</summary>
function Under(const ARelative: string): string;

/// <summary>Aufgezeichnete Ausgabe von git status --porcelain=v2.</summary>
function GitStatusSample: string;

const
  SvnInfoSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<info>'#10 +
    '<entry'#10 +
    '   kind="dir"'#10 +
    '   path="."'#10 +
    '   revision="42">'#10 +
    '<url>https://svn.example.org/repo/projekt/branches/release-2</url>'#10 +
    '<relative-url>^/projekt/branches/release-2</relative-url>'#10 +
    '<repository>'#10 +
    '<root>https://svn.example.org/repo</root>'#10 +
    '<uuid>0c8d5a9e-3f1b-4e7a-9b2c-7d6e5f4a3b2c</uuid>'#10 +
    '</repository>'#10 +
    '<wc-info>'#10 +
    '<wcroot-abspath>C:/Projekte/Kunde</wcroot-abspath>'#10 +
    '<schedule>normal</schedule>'#10 +
    '<depth>infinity</depth>'#10 +
    '</wc-info>'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '</info>'#10;

  SvnStatusSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<status>'#10 +
    '<target'#10 +
    '   path=".">'#10 +
    '<entry'#10 +
    '   path="src\Main.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="modified"'#10 +
    '   revision="42">'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="src\Neu &amp; Alt.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="added"'#10 +
    '   revision="-1">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="notizen.txt">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="unversioned">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="build">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="ignored">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="res\Logo.png">'#10 +
    '<wc-status'#10 +
    '   props="modified"'#10 +
    '   item="normal"'#10 +
    '   revision="42">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="alt.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="deleted"'#10 +
    '   revision="42"/>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="weg.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="missing"'#10 +
    '   revision="42"/>'#10 +
    '</entry>'#10 +
    '</target>'#10 +
    '</status>'#10;

  SvnBlameSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<blame>'#10 +
    '<target'#10 +
    '   path="src\Main.pas">'#10 +
    '<entry'#10 +
    '   line-number="1">'#10 +
    '<commit'#10 +
    '   revision="12">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-09-01T10:00:00.250000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   line-number="2">'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   line-number="3">'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>j&#252;rgen</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '</target>'#10 +
    '</blame>'#10;
  SvnLogSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<log>'#10 +
    '<logentry'#10 +
    '   revision="57">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-27T21:20:00.000000Z</date>'#10 +
    '<paths>'#10 +
    '<path'#10 +
    '   action="M"'#10 +
    '   kind="file"'#10 +
    '   prop-mods="false"'#10 +
    '   text-mods="true">/projekt/branches/ATL-12-tracker/src/Main.pas</path>'#10 +
    '<path'#10 +
    '   action="A"'#10 +
    '   kind="dir">/projekt/branches/ATL-12-tracker/neu</path>'#10 +
    '<path'#10 +
    '   action="D"'#10 +
    '   kind="file">/anderes/trunk/X.pas</path>'#10 +
    '</paths>'#10 +
    '<msg>ATL-12 Tracker &amp; Plugin'#10'Zweite Zeile</msg>'#10 +
    '</logentry>'#10 +
    '<logentry'#10 +
    '   revision="50">'#10 +
    '<author>anna</author>'#10 +
    '<date>2026-10-20T08:00:00.000000Z</date>'#10 +
    '<paths>'#10 +
    '<path'#10 +
    '   action="A"'#10 +
    '   kind="file">/projekt/trunk/src/Neu.pas</path>'#10 +
    '</paths>'#10 +
    '<msg>ATL-12 Anfang</msg>'#10 +
    '</logentry>'#10 +
    '</log>'#10;

  SvnListSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<lists>'#10 +
    '<list'#10 +
    '   path="https://svn.example.org/repo/branches">'#10 +
    '<entry'#10 +
    '   kind="dir">'#10 +
    '<name>ATL-12-tracker</name>'#10 +
    '<commit'#10 +
    '   revision="57">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-27T21:20:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   kind="file">'#10 +
    '<name>liesmich.txt</name>'#10 +
    '<size>4</size>'#10 +
    '<commit'#10 +
    '   revision="3">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-01-01T00:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   kind="dir">'#10 +
    '<name>release-2</name>'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '</list>'#10 +
    '</lists>'#10;

implementation

function Root: string;
begin
  if PathDelim = '\' then
  begin
    Result := 'C:\Projekte\Kunde';
  end
  else
  begin
    Result := '/projekte/kunde';
  end;
end;

function Under(const ARelative: string): string;
begin
  Result := Root + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

function GitStatusSample: string;
begin
  // Aufgezeichnet mit git 2.43: "git status --porcelain=v2 --branch -z --untracked-files=all" nach
  // git mv B.pas C.pas, Änderung an A.pas, gelöschter Datei mit Umlaut und Leerzeichen und zwei neuen Dateien.
  Result :=
    '# branch.oid ' + Hash1 + #0 +
    '# branch.head main' + #0 +
    '1 .M N... 100644 100644 100644 ' + Hash2 + ' ' + Hash2 + ' A.pas' + #0 +
    '2 R. N... 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb ' +
    '587be6b4c3f93f93c489c0111bba5596147a26cb R100 C.pas' + #0 + 'B.pas' + #0 +
    '1 .D N... 100644 100644 000000 975fbec8256d3e8a3797e7a3611380f27c49f4ac ' +
    '975fbec8256d3e8a3797e7a3611380f27c49f4ac ' + #$00DC + ' m.pas' + #0 +
    '? Neu.pas' + #0 +
    '? sub/Q.pas' + #0;
end;

end.
