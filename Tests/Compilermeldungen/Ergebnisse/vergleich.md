# Atlas gegen dcc: Compilermeldungen

| Kennzahl | Anzahl |
|---|---|
| Fälle | 471 |
| nicht gebaut | 0 |
| Fall greift nicht (dcc meldet den erwarteten Code nicht) | 0 |
| Codes, die dcc meldet | 482 |
| davon von Atlas erkannt (strict) | 228 |
| davon auch im Profil standard | 226 |
| Atlas meldet einen anderen Code | 17 |
| verpasst | 237 |
| zusätzliche Atlas-Treffer mit Compiler-Code | 94 |

| Fall | erwartet | dcc meldet | Atlas | Regeln | zusätzlich |
|---|---|---|---|---|---|
| Cm.E1012 | E1012 | E1012 | E1012 verpasst |  |  |
| Cm.E1019 | E1019 | E1019 | E1019 erkannt | for-variable-misuse |  |
| Cm.E1026 | F1026 | F1026 | F1026 verpasst |  |  |
| Cm.E1038 | E1038 | – | E1038 erkannt | unit-name-mismatch |  |
| Cm.E2001 | E2064 | E2064 | E2064 verpasst |  |  |
| Cm.E2001b | E2001 | E2001 | E2001 erkannt | case-selector-not-ordinal |  |
| Cm.E2002 | E2002 | E2002 | E2002 anderer Code | unresolved-type (E2003) | unresolved-type (E2003) |
| Cm.E2003 | E2003 | E2003 | E2003 erkannt | unresolved-identifier |  |
| Cm.E2004 | E2004 | E2004, E2010 | E2004 erkannt; E2010 verpasst | duplicate-declaration |  |
| Cm.E2005 | E2029 | E2029 | E2029 verpasst |  | unresolved-type (E2005) |
| Cm.E2005b | E2007 | E2007 | E2007 verpasst |  | unresolved-type (E2005) |
| Cm.E2006 | E2006 | E2006 | E2006 verpasst |  |  |
| Cm.E2007 | E2029 | E2029 | E2029 erkannt | syntax |  |
| Cm.E2008 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.E2009 | E2009 | E2009 | E2009 verpasst |  |  |
| Cm.E2010 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.E2011 | E2011 | E2011 | E2011 erkannt | constant-expression-error |  |
| Cm.E2012 | E2012 | E2012 | E2012 erkannt | condition-not-boolean |  |
| Cm.E2013 | E2008 | E2008 | E2008 verpasst |  |  |
| Cm.E2014 | E2029 | E2029 | E2029 verpasst |  | comparison-as-statement (E2014) |
| Cm.E2014b | E2014 | E2014 | E2014 erkannt | comparison-as-statement |  |
| Cm.E2015 | E2015 | E2015 | E2015 verpasst |  |  |
| Cm.E2016 | E2016 | E2016 | E2016 verpasst |  |  |
| Cm.E2017 | E2017 | E2017 | E2017 verpasst |  |  |
| Cm.E2018 | E2018 | E2018 | E2018 verpasst |  |  |
| Cm.E2019 | E2019 | E2019 | E2019 verpasst |  |  |
| Cm.E2020 | E2015 | E2015 | E2015 verpasst |  |  |
| Cm.E2021 | E2021 | E2021 | E2021 verpasst |  |  |
| Cm.E2022 | E2022 | E2022 | E2022 verpasst |  |  |
| Cm.E2023 | E2023 | E2023 | E2023 erkannt | syntax |  |
| Cm.E2024 | E2024 | E2024 | E2024 verpasst |  |  |
| Cm.E2025 | E2025 | E2025 | E2025 erkannt | syntax |  |
| Cm.E2026 | E2026 | E2026 | E2026 erkannt | case-selector-not-ordinal |  |
| Cm.E2027 | E2027 | E2027 | E2027 erkannt | duplicate-case-label |  |
| Cm.E2028 | E2028 | E2028 | E2028 verpasst |  |  |
| Cm.E2029 | E2029 | E2029 | E2029 erkannt | syntax |  |
| Cm.E2030 | E2030 | E2030 | E2030 erkannt | duplicate-case-label |  |
| Cm.E2031 | E2031 | E2031 | E2031 erkannt | syntax |  |
| Cm.E2032 | E2032 | E2032 | E2032 erkannt | case-selector-not-ordinal |  |
| Cm.E2033 | E2033 | E2033 | E2033 verpasst |  |  |
| Cm.E2034 | E2034 | E2034 | E2034 erkannt | argument-count-mismatch |  |
| Cm.E2035 | E2035 | E2035 | E2035 erkannt | argument-count-mismatch |  |
| Cm.E2036 | E2036 | E2036 | E2036 verpasst |  |  |
| Cm.E2037 | E2037 | E2010, E2037 | E2010 verpasst; E2037 verpasst |  |  |
| Cm.E2038 | E2038 | E2038 | E2038 erkannt | file-encoding-unsupported | syntax (E2066) |
| Cm.E2049 | E2049 | E2049 | E2049 erkannt | syntax |  |
| Cm.E2050 | E2050 | E2050 | E2050 erkannt | syntax |  |
| Cm.E2052 | E2052 | E2052 | E2052 erkannt | syntax |  |
| Cm.E2053 | E2053 | E2053 | E2053 anderer Code | syntax (E2066), unresolved-identifier (E2003) | syntax (E2066); unresolved-identifier (E2003) |
| Cm.E2054 | E2054 | E2054 | E2054 verpasst |  |  |
| Cm.E2055 | E2055 | E2055 | E2055 verpasst |  |  |
| Cm.E2056 | - | – | – |  | unused-assignment (H2077) |
| Cm.E2057 | E2057 | E2029, E2057 | E2029 verpasst; E2057 erkannt | syntax |  |
| Cm.E2058 | E2058 | E2058, E2059 | E2058 erkannt; E2059 verpasst | syntax |  |
| Cm.E2059 | E2059 | E2059 | E2059 verpasst |  | syntax (E2061) |
| Cm.E2060 | E2058 | E2058, E2059 | E2058 verpasst; E2059 anderer Code | syntax (E2060) | syntax (E2060) |
| Cm.E2061 | E2059 | E2059 | E2059 anderer Code | syntax (E2061) | syntax (E2061) |
| Cm.E2062 | E2062 | E2062 | E2062 verpasst |  |  |
| Cm.E2064 | E2064 | E2064 | E2064 erkannt | typed-constant-modified |  |
| Cm.E2065 | E2065 | E2065 | E2065 erkannt | unsatisfied-forward |  |
| Cm.E2066 | E2066 | E2066 | E2066 erkannt | syntax |  |
| Cm.E2067 | E2067 | E2067 | E2067 erkannt | syntax |  |
| Cm.E2070 | E2070 | E2070 | E2070 erkannt | directive-typo |  |
| Cm.E2071 | E2071 | E2071 | E2071 anderer Code | unresolved-type (E2003) | unresolved-type (E2003) |
| Cm.E2072 | E2072 | E2072 | E2072 erkannt | constant-initializer-mismatch |  |
| Cm.E2073 | E2073 | E2073 | E2073 erkannt | label-misuse |  |
| Cm.E2074 | E2074 | E2074 | E2074 erkannt | label-misuse |  |
| Cm.E2075 | E2076 | E2076 | E2076 verpasst |  |  |
| Cm.E2076 | E2076 | E2076 | E2076 verpasst |  |  |
| Cm.E2077 | E2025 | E2025 | E2025 verpasst |  |  |
| Cm.E2078 | E2078 | E2078 | E2078 anderer Code | unresolved-identifier (E2003) | unresolved-identifier (E2003) |
| Cm.E2079 | E2467 | E2467 | E2467 verpasst |  | unresolved-identifier (E2003) |
| Cm.E2080 | E2019 | E2019 | E2019 verpasst |  | unresolved-identifier (E2003) |
| Cm.E2081 | E2081 | E2081 | E2081 erkannt | for-variable-misuse |  |
| Cm.E2082 | E2019 | E2019 | E2019 verpasst |  |  |
| Cm.E2083 | E2083 | E2083 | E2083 erkannt | constant-initializer-mismatch |  |
| Cm.E2086 | E2086 | E2086 | E2086 verpasst |  |  |
| Cm.E2088 | E2029 | E2029 | E2029 verpasst |  | syntax (E2088) |
| Cm.E2089 | E2089 | E2089 | E2089 verpasst |  |  |
| Cm.E2091 | E2088 | E2088 | E2088 verpasst |  | syntax (E2029) |
| Cm.E2093 | E2093 | E2093 | E2093 erkannt | label-misuse |  |
| Cm.E2094 | E2094 | E2094 | E2094 erkannt | local-routine-as-callback |  |
| Cm.E2095 | E2280 | E2280 | E2280 verpasst |  | syntax (E2029); conditional-directive-unbalanced (E2095) |
| Cm.E2096 | E2029 | E2029, E2065 | E2029 erkannt; E2065 erkannt | syntax; declared-not-implemented | duplicate-declaration (E2004) |
| Cm.E2097 | E2097 | E2097 | E2097 erkannt | jump-outside-allowed-scope |  |
| Cm.E2098 | E2098 | E2098 | E2098 erkannt | constant-expression-error |  |
| Cm.E2099 | E2099 | E2099 | E2099 verpasst |  |  |
| Cm.E2100 | E2100 | E2100 | E2100 erkannt | type-too-large |  |
| Cm.E2102 | E2102 | E2102, W1012 | E2102 erkannt; W1012 verpasst | constant-expression-error |  |
| Cm.E2105 | E2105 | E2105 | E2105 verpasst |  |  |
| Cm.E2107 | E2107 | E2107 | E2107 verpasst |  |  |
| Cm.E2108 | E2107 | E2107 | E2107 verpasst |  |  |
| Cm.E2109 | E2109 | E2109 | E2109 verpasst |  |  |
| Cm.E2111 | E2111 | E2111 | E2111 verpasst |  |  |
| Cm.E2112 | E2105 | E2105 | E2105 verpasst |  |  |
| Cm.E2113 | E2113 | E2113 | E2113 verpasst |  |  |
| Cm.E2114 | E2114 | E2114 | E2114 verpasst |  |  |
| Cm.E2115 | E2003 | E2003 | E2003 verpasst |  |  |
| Cm.E2116 | E2107 | E2107 | E2107 verpasst |  |  |
| Cm.E2118 | E2118 | E2118 | E2118 verpasst |  |  |
| Cm.E2119 | E2003 | E2003 | E2003 verpasst |  |  |
| Cm.E2121 | - | – | – |  | exports-invalid (E2121) |
| Cm.E2121b | E2276 | E2276 | E2276 verpasst |  | exports-invalid (E2121) |
| Cm.E2123 | E2123 | E2123 | E2123 anderer Code | syntax (E2357) | syntax (E2357) |
| Cm.E2124 | E2124 | E2124 | E2124 erkannt | inaccessible-member |  |
| Cm.E2125 | E2125 | E2125 | E2125 erkannt | syntax |  |
| Cm.E2126 | E2126 | E2126, H2077 | E2126 erkannt; H2077 erkannt | jump-outside-allowed-scope; unused-assignment |  |
| Cm.E2127 | E2127 | E2127 | E2127 erkannt | label-misuse |  |
| Cm.E2129 | E2129 | E2129 | E2129 erkannt | readonly-property-assigned |  |
| Cm.E2130 | E2130 | E2130 | E2130 erkannt | readonly-property-assigned |  |
| Cm.E2131 | E2131 | E2131 | E2131 verpasst |  |  |
| Cm.E2132 | E2132 | E2132 | E2132 erkannt | default-property-invalid |  |
| Cm.E2133 | E2133 | E2133 | E2133 erkannt | typeinfo-invalid |  |
| Cm.E2134 | E2134 | E2134 | E2134 erkannt | typeinfo-invalid |  |
| Cm.E2136 | E2136 | E2136 | E2136 erkannt | abstract-declaration-invalid |  |
| Cm.E2137 | E2137 | E2137 | E2137 erkannt | override-target-missing |  |
| Cm.E2138 | E2138 | E2138 | E2138 erkannt | message-method-invalid |  |
| Cm.E2139 | E2139 | E2139 | E2139 erkannt | message-method-invalid |  |
| Cm.E2140 | E2140 | E2140 | E2140 erkannt | message-method-invalid |  |
| Cm.E2143 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.E2145 | E2145 | E2145 | E2145 erkannt | reraise-outside-handler |  |
| Cm.E2146 | - | – | – |  | default-parameter-invalid (E2146) |
| Cm.E2147 | E2147 | E2147 | E2147 erkannt | property-redeclaration-invalid |  |
| Cm.E2148 | E2169 | E2029, E2169 | E2029 verpasst; E2169 verpasst |  |  |
| Cm.E2149 | E2149 | E2149 | E2149 erkannt | default-property-invalid |  |
| Cm.E2150 | E2150 | E2150 | E2150 verpasst |  |  |
| Cm.E2153 | E2153 | E2153 | E2153 erkannt | syntax |  |
| Cm.E2154 | E2154 | E2154 | E2154 erkannt | variant-record-managed-field |  |
| Cm.E2155 | E2155 | E2155 | E2155 erkannt | variant-record-managed-field |  |
| Cm.E2157 | E2157 | E2157 | E2157 verpasst |  |  |
| Cm.E2160 | E2160 | E2160 | E2160 verpasst |  |  |
| Cm.E2166 | E2166 | E2166 | E2166 verpasst |  |  |
| Cm.E2167 | E2167 | E2065, E2167 | E2065 anderer Code; E2167 erkannt | abstract-declaration-invalid (E2167); abstract-declaration-invalid |  |
| Cm.E2168 | E2168 | E2168 | E2168 erkannt | property-accessor-invalid |  |
| Cm.E2169 | E2169 | E2169 | E2169 erkannt | field-after-method |  |
| Cm.E2170 | E2170 | E2170 | E2170 erkannt | override-target-missing |  |
| Cm.E2173 | E2173 | E2173 | E2173 erkannt | conditional-directive-unbalanced |  |
| Cm.E2174 | E2008 | E2008 | E2008 verpasst |  | property-accessor-invalid (E2174) |
| Cm.E2175 | E2175 | E2175, H2219, W1000 | E2175 verpasst; H2219 verpasst; W1000 verpasst |  |  |
| Cm.E2176 | E2176 | E2176, W1000 | E2176 verpasst; W1000 verpasst |  |  |
| Cm.E2177 | E2177 | E2177, W1000 | E2177 verpasst; W1000 verpasst |  |  |
| Cm.E2178 | E2178 | E2178, W1000 | E2178 verpasst; W1000 verpasst |  |  |
| Cm.E2179 | E2179 | E2179, W1000 | E2179 verpasst; W1000 verpasst |  |  |
| Cm.E2180 | E2180 | E2180, W1000 | E2180 verpasst; W1000 verpasst |  |  |
| Cm.E2181 | E2181 | E2096, E2128, E2181, W1000 | E2096 verpasst; E2128 verpasst; E2181 verpasst; W1000 verpasst |  |  |
| Cm.E2182 | E2182 | E2182, W1000 | E2182 verpasst; W1000 verpasst |  |  |
| Cm.E2183 | E2185 | E2169, E2185 | E2169 verpasst; E2185 verpasst |  |  |
| Cm.E2185 | E2185 | E2169, E2185, H2219, W1000 | E2169 verpasst; E2185 verpasst; H2219 verpasst; W1000 verpasst |  |  |
| Cm.E2186 | E2186 | E2186, W1055 | E2186 erkannt; W1055 verpasst | published-type-invalid |  |
| Cm.E2187 | E2187 | E2187, W1055 | E2187 erkannt; W1055 verpasst | published-type-invalid |  |
| Cm.E2188 | E2188 | E2188, W1055 | E2188 erkannt; W1055 verpasst | published-type-invalid |  |
| Cm.E2189 | E2189 | E2189 | E2189 erkannt | type-restriction-violated |  |
| Cm.E2190 | E2190 | E2190 | E2190 erkannt | type-restriction-violated |  |
| Cm.E2191 | E2191 | E2191 | E2191 erkannt | exports-invalid |  |
| Cm.E2192 | E2197 | E2197 | E2197 verpasst |  | invalid-var-argument (E2192) |
| Cm.E2193 | E2193 | E2193 | E2193 verpasst |  |  |
| Cm.E2194 | E2194 | E2194 | E2194 erkannt | type-restriction-violated |  |
| Cm.E2195 | E2195 | E2195 | E2195 erkannt | syntax |  |
| Cm.E2196 | E2196 | E2196 | E2196 erkannt | syntax |  |
| Cm.E2197 | E2197 | E2197 | E2197 erkannt | invalid-var-argument, typed-constant-modified |  |
| Cm.E2198 | E2008 | E2008 | E2008 verpasst |  |  |
| Cm.E2204 | E2204 | E2204 | E2204 erkannt | guid-syntax-invalid |  |
| Cm.E2205 | E2205 | E2205 | E2205 erkannt | interface-declaration-invalid |  |
| Cm.E2206 | E2206 | E2128, E2206 | E2128 verpasst; E2206 erkannt | interface-declaration-invalid |  |
| Cm.E2207 | E2207 | E2207 | E2207 erkannt | interface-declaration-invalid |  |
| Cm.E2208 | E2208 | E2208 | E2208 erkannt | interface-declaration-invalid |  |
| Cm.E2209 | E2209 | E2209, H2219 | E2209 erkannt; H2219 verpasst | interface-declaration-invalid |  |
| Cm.E2210 | E2070 | E2070 | E2070 verpasst |  | interface-declaration-invalid (E2210) |
| Cm.E2211 | E2291 | E2291 | E2291 verpasst |  | interface-not-implemented (E2211) |
| Cm.E2217 | E2217 | E2217, W1055 | E2217 erkannt; W1055 verpasst | published-type-invalid |  |
| Cm.E2218 | W1055 | W1055 | W1055 verpasst |  |  |
| Cm.E2221 | - | – | – |  |  |
| Cm.E2222 | E2222 | E2222 | E2222 verpasst |  |  |
| Cm.E2224 | E2224 | E2224 | E2224 verpasst |  |  |
| Cm.E2228 | E2228 | E2228 | E2228 verpasst |  |  |
| Cm.E2229 | E2229 | E2229 | E2229 verpasst |  |  |
| Cm.E2230 | E2230 | E2230 | E2230 verpasst |  |  |
| Cm.E2231 | E2231 | E2231 | E2231 verpasst |  |  |
| Cm.E2232 | E2232 | E2232 | E2232 verpasst |  |  |
| Cm.E2233 | E2147 | E2147 | E2147 erkannt | property-redeclaration-invalid |  |
| Cm.E2234 | E2008 | E2008 | E2008 verpasst |  | property-accessor-invalid (E2234) |
| Cm.E2236 | E2236 | E2236 | E2236 erkannt | calling-convention-required |  |
| Cm.E2237 | E2237 | E2237 | E2237 erkannt | default-parameter-invalid |  |
| Cm.E2238 | E2238 | E2238 | E2238 erkannt | default-parameter-invalid |  |
| Cm.E2239 | E2239 | E2239 | E2239 erkannt | default-parameter-invalid |  |
| Cm.E2240 | E2003 | E2003, H2077 | E2003 verpasst; H2077 erkannt | unused-assignment |  |
| Cm.E2242 | E2003 | E2003 | E2003 verpasst |  | unit-name-conflict (E2242) |
| Cm.E2243 | H2243 | H2243 | H2243 verpasst |  |  |
| Cm.E2245 | E2245 | – | E2245 verpasst |  |  |
| Cm.E2246 | E2246 | E2246 | E2246 erkannt | dynamic-array-misuse |  |
| Cm.E2250 | E2250 | E2250 | E2250 verpasst |  |  |
| Cm.E2251 | E2251 | E2251 | E2251 verpasst |  |  |
| Cm.E2252 | E2004 | E2004 | E2004 verpasst |  | overload-directive-missing (E2252) |
| Cm.E2254 | E2254 | E2254 | E2254 erkannt | overload-directive-missing |  |
| Cm.E2255 | E2255 | E2255 | E2255 erkannt | dynamic-array-misuse |  |
| Cm.E2256 | E2008 | E2008 | E2008 verpasst |  | dynamic-array-misuse (E2256) |
| Cm.E2257 | E2257 | E2257 | E2257 erkannt | implements-clause-invalid |  |
| Cm.E2258 | E2258 | E2258 | E2258 erkannt | implements-clause-invalid |  |
| Cm.E2259 | E2259 | E2259 | E2259 erkannt | implements-clause-invalid |  |
| Cm.E2260 | E2260 | E2260 | E2260 erkannt | implements-clause-invalid |  |
| Cm.E2261 | E2261 | E2261 | E2261 erkannt | implements-clause-invalid |  |
| Cm.E2262 | E2262 | E2262 | E2262 erkannt | implements-clause-invalid |  |
| Cm.E2263 | E2263 | E2148, E2263 | E2148 anderer Code; E2263 erkannt | implements-clause-invalid (E2263); implements-clause-invalid |  |
| Cm.E2264 | E2264 | E2264, H2219 | E2264 erkannt; H2219 verpasst | implements-clause-invalid |  |
| Cm.E2265 | E2003 | E2003, H2219 | E2003 verpasst; H2219 verpasst |  | interface-not-implemented (E2265) |
| Cm.E2266 | E2266 | E2266, W1055 | E2266 erkannt; W1055 verpasst | published-type-invalid |  |
| Cm.E2267 | E2267 | E2267 | E2267 erkannt | overload-directive-missing |  |
| Cm.E2268 | E2268 | E2268 | E2268 erkannt | default-parameter-invalid | syntax (E2029) |
| Cm.E2270 | E2270 | E2270, W1055 | E2270 erkannt; W1055 verpasst | calling-convention-required |  |
| Cm.E2271 | H2219 | H2219 | H2219 verpasst |  |  |
| Cm.E2273 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.E2274 | E2029 | E2029 | E2029 verpasst |  |  |
| Cm.E2275 | E2029 | E2029 | E2029 verpasst |  |  |
| Cm.E2276 | E2276 | E2276 | E2276 erkannt | exports-invalid |  |
| Cm.E2277 | E2277 | E2277 | E2277 verpasst |  |  |
| Cm.E2278 | F2084 | E2026, F2084 | E2026 verpasst; F2084 verpasst |  | local-routine-as-callback (E2278) |
| Cm.E2279 | E1030 | E1030 | E1030 verpasst |  | conditional-directive-unbalanced (E2279) |
| Cm.E2280 | E2280 | E2280 | E2280 erkannt | conditional-directive-unbalanced | syntax (E2029) |
| Cm.E2281 | E2281 | E2281 | E2281 verpasst |  |  |
| Cm.E2282 | E2282 | E2282 | E2282 erkannt | property-accessor-invalid |  |
| Cm.E2289 | E1074 | E1074 | E1074 verpasst |  |  |
| Cm.E2291 | E2291 | E2291 | E2291 erkannt | interface-not-implemented |  |
| Cm.E2292 | E2168 | E2029, E2168 | E2029 anderer Code; E2168 erkannt | property-accessor-invalid (E2168); property-accessor-invalid |  |
| Cm.E2294 | E2294 | E2294 | E2294 erkannt | type-restriction-violated |  |
| Cm.E2295 | E2295 | E2295 | E2295 erkannt | type-restriction-violated |  |
| Cm.E2296 | - | – | – |  | line-length (F2069) |
| Cm.E2299 | E2029 | E2029 | E2029 erkannt | syntax |  |
| Cm.E2301 | E2252 | E2065, E2252 | E2065 erkannt; E2252 erkannt | declared-not-implemented; overload-directive-missing |  |
| Cm.E2306 | - | – | – |  |  |
| Cm.E2307 | E2008 | E2008 | E2008 verpasst |  |  |
| Cm.E2308 | E2255 | E2255 | E2255 verpasst |  | dynamic-array-misuse (E2308) |
| Cm.E2325 | - | – | – |  | attribute-usage-invalid (E2325) |
| Cm.E2326 | - | – | – |  | attribute-usage-invalid (E2326) |
| Cm.E2351 | E2351 | E2351 | E2351 erkannt | abstract-declaration-invalid |  |
| Cm.E2352 | E2352 | E2352 | E2352 erkannt | override-target-missing |  |
| Cm.E2353 | E2353 | E2353 | E2353 erkannt | override-target-missing |  |
| Cm.E2354 | - | – | – |  | invalid-var-argument (E2354) |
| Cm.E2355 | E2355 | E2355 | E2355 erkannt | property-accessor-invalid |  |
| Cm.E2356 | E2356 | E2356 | E2356 erkannt | property-accessor-invalid |  |
| Cm.E2357 | E2029 | E2029 | E2029 erkannt | syntax |  |
| Cm.E2358 | - | – | – |  |  |
| Cm.E2359 | E2359 | E2359 | E2359 erkannt | type-restriction-violated |  |
| Cm.E2360 | E2360 | E2360 | E2360 erkannt | type-restriction-violated |  |
| Cm.E2361 | E2361 | E2361 | E2361 erkannt | inaccessible-member |  |
| Cm.E2362 | E2362 | E2362 | E2362 erkannt | inaccessible-member |  |
| Cm.E2366 | E2009 | E2009 | E2009 verpasst |  |  |
| Cm.E2370 | - | – | – |  |  |
| Cm.E2371 | E2371 | E2371 | E2371 erkannt | abstract-declaration-invalid |  |
| Cm.E2372 | E2029 | E2029 | E2029 verpasst |  | syntax (E2066) |
| Cm.E2373 | - | – | – |  | inherited-abstract-call (E2373) |
| Cm.E2374 | E2005 | E2005 | E2005 verpasst |  |  |
| Cm.E2375 | E2375 | E2375 | E2375 erkannt | syntax |  |
| Cm.E2376 | E2376 | E2376 | E2376 erkannt | abstract-declaration-invalid |  |
| Cm.E2379 | E2379 | E2379 | E2379 erkannt | type-restriction-violated |  |
| Cm.E2380 | E2009 | E2009 | E2009 verpasst |  |  |
| Cm.E2381 | E2381 | E2381 | E2381 erkannt | string-length-limit |  |
| Cm.E2382 | - | – | – |  |  |
| Cm.E2383 | E2383 | E2383, E2540 | E2383 erkannt; E2540 verpasst | abstract-declaration-invalid |  |
| Cm.E2389 | E2362 | E2362 | E2362 verpasst |  |  |
| Cm.E2393 | E2393 | E2029, E2037, E2393 | E2029 anderer Code; E2037 verpasst; E2393 erkannt | operator-declaration-invalid (E2393); operator-declaration-invalid |  |
| Cm.E2394 | E2394 | E2394 | E2394 erkannt | type-restriction-violated |  |
| Cm.E2398 | E2398 | E2398 | E2398 erkannt | type-restriction-violated |  |
| Cm.E2399 | - | – | – |  |  |
| Cm.E2402 | - | – | – |  | abstract-class-instantiated (E2402) |
| Cm.E2404 | E2029 | E2029, E2037, E2065, H2219 | E2029 verpasst; E2037 verpasst; E2065 verpasst; H2219 verpasst |  |  |
| Cm.E2412 | E2029 | E2029 | E2029 verpasst |  | syntax (E2066) |
| Cm.E2413 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.E2418 | E2154 | E2154 | E2154 erkannt | variant-record-managed-field |  |
| Cm.E2419 | - | – | – |  |  |
| Cm.E2420 | E2086 | E2086 | E2086 verpasst |  |  |
| Cm.E2423 | H2077 | H2077 | H2077 verpasst |  |  |
| Cm.E2424 | E1030 | E1030 | E1030 verpasst |  |  |
| Cm.E2425 | E2425 | E2425 | E2425 erkannt | type-restriction-violated |  |
| Cm.E2426 | E2426 | E2426 | E2426 erkannt | type-restriction-violated |  |
| Cm.E2430 | E2430 | E2430 | E2430 erkannt | for-in-not-enumerable |  |
| Cm.E2431 | E2431 | E2431 | E2431 erkannt | for-in-not-enumerable |  |
| Cm.E2432 | E2029 | E2029 | E2029 verpasst |  |  |
| Cm.E2433 | E2433 | E2065, E2433 | E2065 anderer Code; E2433 erkannt | type-restriction-violated (E2433); type-restriction-violated |  |
| Cm.E2434 | E2434 | E2434 | E2434 erkannt | type-restriction-violated |  |
| Cm.E2435 | E2435 | E2435 | E2435 erkannt | type-restriction-violated |  |
| Cm.E2436 | E2436 | E2436 | E2436 erkannt | type-restriction-violated |  |
| Cm.E2437 | E2437 | E2437 | E2437 erkannt | type-restriction-violated |  |
| Cm.E2439 | E2439 | E2439 | E2439 erkannt | type-restriction-violated |  |
| Cm.E2441 | E2441 | E2441 | E2441 erkannt | type-restriction-violated |  |
| Cm.E2442 | E2442 | E2442 | E2442 erkannt | type-restriction-violated |  |
| Cm.E2448 | E2026 | E2026 | E2026 verpasst |  | attribute-usage-invalid (E2448) |
| Cm.E2449 | E2449 | E2449 | E2449 erkannt | type-restriction-violated |  |
| Cm.E2450 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.E2452 | W1055 | W1055 | W1055 verpasst |  | published-type-invalid (E2452) |
| Cm.E2453 | E2064 | E2064 | E2064 verpasst |  |  |
| Cm.E2454 | - | – | – |  |  |
| Cm.E2459 | E2459 | E2029, E2459 | E2029 verpasst; E2459 verpasst |  |  |
| Cm.E2460 | E2021 | E2021 | E2021 verpasst |  |  |
| Cm.E2461 | E2356 | E2356 | E2356 erkannt | property-accessor-invalid |  |
| Cm.E2463 | E2379 | E2379 | E2379 erkannt | type-restriction-violated |  |
| Cm.E2464 | E2617 | E2617 | E2617 verpasst |  | operator-declaration-invalid (E2464) |
| Cm.E2465 | E2465 | E2465 | E2465 erkannt | type-restriction-violated |  |
| Cm.E2467 | E2018 | E2018 | E2018 verpasst |  |  |
| Cm.E2471 | E2471 | E2471 | E2471 erkannt | type-restriction-violated |  |
| Cm.E2474 | E2474 | E2474 | E2474 verpasst |  |  |
| Cm.E2475 | E2379 | E2379 | E2379 verpasst |  | type-restriction-violated (E2598) |
| Cm.E2501 | E2501 | E2501 | E2501 erkannt | type-restriction-violated |  |
| Cm.E2506 | E2506 | E2506 | E2506 erkannt | generic-declaration-invalid |  |
| Cm.E2507 | E2507 | E2507 | E2507 erkannt | generic-declaration-invalid |  |
| Cm.E2508 | E2508 | E2508 | E2508 erkannt | generic-declaration-invalid |  |
| Cm.E2510 | E2510 | E2510 | E2510 erkannt | generic-declaration-invalid |  |
| Cm.E2511 | E2511 | E2511 | E2511 erkannt | generic-constraint-violated |  |
| Cm.E2512 | E2512 | E2512 | E2512 erkannt | generic-constraint-violated |  |
| Cm.E2513 | E2513 | E2513 | E2513 erkannt | generic-constraint-violated |  |
| Cm.E2514 | E2514 | E2514 | E2514 erkannt | generic-constraint-violated |  |
| Cm.E2515 | E2515 | E2515 | E2515 erkannt | generic-constraint-violated |  |
| Cm.E2516 | E2516 | E2516 | E2516 erkannt | generic-declaration-invalid |  |
| Cm.E2517 | E2517 | E2517 | E2517 erkannt | operator-declaration-invalid |  |
| Cm.E2518 | E2518 | E2518 | E2518 erkannt | operator-declaration-invalid |  |
| Cm.E2519 | E2519 | E2519 | E2519 erkannt | operator-declaration-invalid |  |
| Cm.E2520 | - | – | – |  |  |
| Cm.E2521 | E2521 | E2521 | E2521 erkannt | operator-declaration-invalid |  |
| Cm.E2522 | E2029 | E2029, E2037, E2123 | E2029 anderer Code; E2037 verpasst; E2123 verpasst | operator-declaration-invalid (E2522) | operator-declaration-invalid (E2522) |
| Cm.E2527 | E2527 | E2527 | E2527 erkannt | type-restriction-violated |  |
| Cm.E2528 | E2528 | E2528 | E2528 verpasst |  |  |
| Cm.E2529 | E2529 | E2065, E2529 | E2065 erkannt; E2529 erkannt | declared-not-implemented; generic-declaration-invalid |  |
| Cm.E2530 | E2530 | E2530 | E2530 erkannt | generic-declaration-invalid |  |
| Cm.E2531 | E2531 | E2531 | E2531 verpasst |  | unresolved-identifier (E2003) |
| Cm.E2532 | E2532 | E2532 | E2532 verpasst |  |  |
| Cm.E2533 | E2533 | E2533 | E2533 erkannt | generic-declaration-invalid |  |
| Cm.E2534 | E2534 | E2534 | E2534 erkannt | type-restriction-violated |  |
| Cm.E2535 | E2535 | E2535 | E2535 erkannt | generic-declaration-invalid |  |
| Cm.E2537 | E2537 | E2537 | E2537 erkannt | typeinfo-invalid |  |
| Cm.E2538 | E2538 | E2015, E2538 | E2015 anderer Code; E2538 erkannt | typeinfo-invalid (E2538), unresolved-identifier (E2003); typeinfo-invalid | unresolved-type (E2003); unresolved-identifier (E2003) |
| Cm.E2539 | E2539 | E2539, E2540 | E2539 verpasst; E2540 verpasst |  |  |
| Cm.E2540 | E2540 | E2383, E2539, E2540 | E2383 verpasst; E2539 verpasst; E2540 verpasst |  |  |
| Cm.E2543 | E2100 | E2100 | E2100 verpasst |  |  |
| Cm.E2545 | E2545 | E2545, W1055 | E2545 erkannt; W1055 verpasst | published-type-invalid |  |
| Cm.E2548 | E2029 | E2029 | E2029 verpasst |  | generic-declaration-invalid (E2548) |
| Cm.E2549 | - | – | – |  | generic-declaration-invalid (E2549) |
| Cm.E2551 | E2551 | E2551 | E2551 erkannt | generic-declaration-invalid |  |
| Cm.E2552 | E2552 | E2552 | E2552 verpasst |  |  |
| Cm.E2553 | E2553 | E2553 | E2553 verpasst |  |  |
| Cm.E2555 | E2555 | E2555 | E2555 erkannt | anonymous-capture-invalid |  |
| Cm.E2556 | E2003 | E2003, E2029 | E2003 verpasst; E2029 verpasst |  | unresolved-type (E2005) |
| Cm.E2560 | E2560 | E2560 | E2560 verpasst |  |  |
| Cm.E2561 | - | – | – |  |  |
| Cm.E2562 | E2029 | E2029 | E2029 verpasst |  |  |
| Cm.E2564 | E2003 | E2003 | E2003 verpasst |  | unresolved-type (E2564) |
| Cm.E2565 | W1074 | W1074 | W1074 verpasst |  | generic-declaration-invalid (E2549); generic-declaration-invalid (E2565) |
| Cm.E2568 | E2568 | E2568 | E2568 erkannt | generic-constraint-violated | unresolved-identifier (E2003) |
| Cm.E2569 | E2569 | E2569 | E2569 erkannt | variant-record-managed-field |  |
| Cm.E2570 | E2570 | E2570 | E2570 verpasst |  |  |
| Cm.E2571 | E2003 | E2003 | E2003 verpasst |  | generic-constraint-violated (E2571) |
| Cm.E2572 | E2572 | E2572 | E2572 verpasst |  |  |
| Cm.E2573 | E1030 | E1030 | E1030 verpasst |  | conditional-directive-unbalanced (E2573) |
| Cm.E2574 | E2574 | E2574 | E2574 verpasst |  |  |
| Cm.E2584 | E2584 | E2584 | E2584 erkannt | attribute-usage-invalid |  |
| Cm.E2589 | E2589 | E2029, E2589 | E2029 verpasst; E2589 erkannt | type-restriction-violated |  |
| Cm.E2591 | - | – | – |  | calling-convention-required (E2277) |
| Cm.E2598 | E2379 | E2379 | E2379 verpasst |  | type-restriction-violated (E2598) |
| Cm.E2599 | E2599 | E2029, E2599 | E2029 anderer Code; E2599 erkannt | type-restriction-violated (E2599); type-restriction-violated |  |
| Cm.E2601 | E2601 | E2601 | E2601 anderer Code | unresolved-identifier (E2003) | unresolved-identifier (E2003) |
| Cm.E2602 | E2602 | E2602 | E2602 anderer Code | unresolved-identifier (E2003) | unresolved-identifier (E2003); unresolved-identifier (E2003) |
| Cm.E2603 | E2603 | E2603 | E2603 erkannt | generic-declaration-invalid |  |
| Cm.F2047 | F2047 | – | F2047 erkannt | uses-cycle |  |
| Cm.F2069 | - | – | – |  | line-length (F2069) |
| Cm.F2092 | F2092 | F2092 | F2092 erkannt | uses-unit-not-found | uses-cycle (F2047) |
| Cm.F2438 | F2438 | F2438 | F2438 erkannt | file-encoding-unsupported | syntax (E2029); line-length (F2069); line-length (F2069) |
| Cm.F2613 | F2613 | F2613 | F2613 erkannt | uses-unit-not-found |  |
| Cm.H1054 | H1054 | H1054 | H1054 verpasst |  |  |
| Cm.H2077 | H2077 | H2077 | H2077 erkannt | unused-assignment |  |
| Cm.H2135 | H2135 | H2135, H2164 | H2135 erkannt; H2164 verpasst | for-high-to-low |  |
| Cm.H2164 | H2164 | H2164 | H2164 erkannt | unused-local |  |
| Cm.H2219 | H2219 | H2219 | H2219 erkannt | unused-private-member |  |
| Cm.H2244 | H2244 | H2244 | H2244 verpasst |  |  |
| Cm.H2269 | H2269 | H2269 | H2269 erkannt | override-case-mismatch |  |
| Cm.H2365 | H2365 | H2365 | H2365 erkannt | override-case-mismatch |  |
| Cm.H2367 | - | – | – |  | override-case-mismatch (H2367) |
| Cm.H2368 | W1055 | W1055 | W1055 verpasst |  |  |
| Cm.H2369 | - | – | – |  |  |
| Cm.H2440 | - | – | – |  | override-case-mismatch (H2440) |
| Cm.H2443 | H2443 | H2443 | H2443 erkannt | inline-not-expanded |  |
| Cm.H2444 | - | – | – |  |  |
| Cm.H2445 | H2445 | H2445 | H2445 verpasst |  |  |
| Cm.H2456 | - | – | – |  | uses-cycle (F2047) |
| Cm.H2457 | - | – | – |  | uses-cycle (F2047) |
| Cm.H2505 | - | – | – |  | inherited-constructor-after-try (H2505) |
| Cm.H2509 | H2509 | H2509 | H2509 erkannt | generic-declaration-invalid |  |
| Cm.W1000 | W1000 | W1000 | W1000 erkannt | deprecated-symbol |  |
| Cm.W1001 | E2029 | E2029 | E2029 verpasst |  |  |
| Cm.W1002 | W1002 | W1002 | W1002 verpasst |  |  |
| Cm.W1003 | W1003 | W1003 | W1003 erkannt | deprecated-symbol |  |
| Cm.W1004 | W1004 | W1004 | W1004 verpasst |  |  |
| Cm.W1005 | W1005 | W1005 | W1005 verpasst |  |  |
| Cm.W1006 | W1006 | W1006 | W1006 erkannt | deprecated-symbol |  |
| Cm.W1007 | W1007 | W1007 | W1007 erkannt | deprecated-symbol |  |
| Cm.W1008 | W1008 | W1008 | W1008 verpasst |  | hresult-integer-mix (X1008) |
| Cm.W1009 | - | – | – |  | member-hides-ancestor (W1009) |
| Cm.W1009b | W1009 | W1009 | W1009 erkannt | member-hides-ancestor |  |
| Cm.W1010 | W1010 | W1010 | W1010 erkannt | hides-virtual |  |
| Cm.W1011 | W1011 | W1011 | W1011 erkannt | text-after-final-end |  |
| Cm.W1012 | E1012 | E1012 | E1012 verpasst |  |  |
| Cm.W1013 | E2010 | E2010 | E2010 verpasst |  |  |
| Cm.W1014 | W1014 | W1014 | W1014 erkannt | string-length-limit |  |
| Cm.W1015 | W1015 | W1015 | W1015 erkannt | for-variable-misuse |  |
| Cm.W1016 | - | – | – |  |  |
| Cm.W1017 | - | – | – |  |  |
| Cm.W1018 | E1012 | E1012 | E1012 verpasst |  |  |
| Cm.W1019 | W1019 | W1019 | W1019 verpasst |  | for-variable-misuse (E1019) |
| Cm.W1020 | W1020 | W1020 | W1020 erkannt | abstract-class-instantiated |  |
| Cm.W1021 | W1021 | W1021 | W1021 erkannt | comparison-always-constant |  |
| Cm.W1022 | W1022 | W1022 | W1022 erkannt | comparison-always-constant |  |
| Cm.W1023 | W1023 | W1023 | W1023 erkannt | signed-unsigned-mix |  |
| Cm.W1024 | W1024 | W1024 | W1024 erkannt | signed-unsigned-mix |  |
| Cm.W1025 | - | – | – |  |  |
| Cm.W1026 | E1026 | E1026 | E1026 verpasst |  |  |
| Cm.W1029 | W1029 | W1029, W1031 | W1029 verpasst; W1031 verpasst |  |  |
| Cm.W1030 | E1030 | E1030 | E1030 verpasst |  |  |
| Cm.W1034 | - | – | – |  |  |
| Cm.W1035 | W1035 | W1035 | W1035 erkannt | result-not-set |  |
| Cm.W1036 | W1036 | W1036 | W1036 erkannt | possibly-uninitialized |  |
| Cm.W1037 | W1037 | W1037 | W1037 erkannt | for-variable-after-loop |  |
| Cm.W1038 | E1038 | E1038 | E1038 erkannt | unit-name-mismatch |  |
| Cm.W1040 | - | – | – |  | implicit-variants-unit (W1040) |
| Cm.W1044 | W1044 | W1044 | W1044 erkannt | suspicious-string-pointer-cast |  |
| Cm.W1045 | E2168 | E2168 | E2168 verpasst |  |  |
| Cm.W1046 | - | – | – |  |  |
| Cm.W1047 | W1047 | W1047 | W1047 verpasst |  |  |
| Cm.W1048 | W1048 | W1048 | W1048 verpasst |  |  |
| Cm.W1050 | W1050 | W1050 | W1050 verpasst |  |  |
| Cm.W1054 | W1054 | W1054 | W1054 verpasst |  |  |
| Cm.W1055 | W1055 | W1055 | W1055 verpasst |  |  |
| Cm.W1057 | W1057 | W1057 | W1057 verpasst |  |  |
| Cm.W1058 | W1058 | W1058 | W1058 verpasst |  |  |
| Cm.W1059 | W1059 | W1059 | W1059 verpasst |  |  |
| Cm.W1060 | W1060 | W1060 | W1060 verpasst |  |  |
| Cm.W1061 | - | – | – |  |  |
| Cm.W1062 | W1062 | W1058, W1062 | W1058 verpasst; W1062 verpasst |  |  |
| Cm.W1063 | - | – | – |  |  |
| Cm.W1064 | - | – | – |  |  |
| Cm.W1066 | - | – | – |  |  |
| Cm.W1068 | W1068 | W1068 | W1068 verpasst |  |  |
| Cm.W1069 | - | – | – |  | conditional-directive-unbalanced (W1030) |
| Cm.W1070 | - | – | – |  | untyped-pointer-refcount (W1070) |
| Cm.W1071 | - | – | – |  | narrowing-assignment (W1071) |
| Cm.W1072 | - | – | – |  |  |
| Cm.W1073 | W1073 | W1073 | W1073 erkannt | signed-unsigned-mix |  |
| Cm.W1074 | W1074 | W1074 | W1074 erkannt | unresolved-attribute |  |
| Cm.W1075 | - | – | – |  | duplicate-declaration (E2004) |
| Cm.W1076 | E1030 | E1030 | E1030 verpasst |  |  |
| Cm.W1077 | E1030 | E1030 | E1030 verpasst |  |  |
| Cm.W1078 | W1078 | W1078 | W1078 erkannt | conditional-directive-unbalanced |  |
| Cm.W1079 | W1079 | W1079 | W1079 erkannt | conditional-directive-unbalanced |  |
| Cm.W1201 | - | – | – |  | xmldoc-mismatch (W1201, W1202, W1203, W1204, W1205, W1206, W1207, W1208) |
| Cm.W1202 | - | – | – |  | xmldoc-mismatch (W1202) |
| Cm.W1203 | - | – | – |  | xmldoc-mismatch (W1201) |
| Cm.W1204 | W1205 | W1205 | W1205 erkannt | xmldoc-mismatch | xmldoc-mismatch (W1204) |
| Cm.W1205 | - | – | – |  | xmldoc-mismatch (W1205); xmldoc-mismatch (W1201, W1202, W1203, W1204, W1205, W1206, W1207, W1208) |
| Cm.W1206 | W1206 | W1206 | W1206 erkannt | xmldoc-mismatch |  |
| Cm.W1207 | W1207 | W1207, W1208 | W1207 erkannt; W1208 erkannt | xmldoc-mismatch; xmldoc-mismatch |  |
| Cm.W1208 | W1208 | W1208 | W1208 erkannt | xmldoc-mismatch |  |
| CmE2085 | E1038 | – | E1038 erkannt | unit-name-mismatch | unit-name-mismatch (E2085) |
| CmE2200 | E2200 | E2200 | E2200 verpasst |  |  |
| CmE2202 | E2202 | E2202 | E2202 verpasst |  |  |
| CmE2214 | E2202 | E2202 | E2202 verpasst |  |  |
| CmE2223 | E2223 | E2223 | E2223 verpasst |  |  |
| CmE2227 | E2654 | E2654 | E2654 verpasst |  |  |
| CmE2272 | E2004 | E2004 | E2004 verpasst |  |  |
| CmE2287 | - | – | – |  | exports-invalid (E2287) |
| CmE2406 | W1002 | W1002 | W1002 verpasst |  |  |
| CmF1026 | F1026 | F1026 | F1026 verpasst |  |  |
| CmH2235 | - | – | – |  |  |
| CmW1032 | W1032 | W1032 | W1032 verpasst |  |  |
| CmW1033 | W1033 | W1033 | W1033 verpasst |  |  |
| CmW1043 | - | – | – |  |  |
