import pymupdf
CSS="""
* {font-family: sans-serif;}
body {color:#606060;}
.name {font-size:20.5pt; font-weight:bold; color:#111111; margin:0;}
.sub {font-size:10.5pt; color:#111111; margin:2pt 0 0 0;}
.contact {font-size:9pt; color:#111111; margin:0;}
.mail {font-size:10pt; color:#0563c1; text-decoration:underline; margin:0;}
h2 {font-size:9.5pt; font-weight:bold; color:#969696; margin:12pt 0 4pt 0;}
p {font-size:9.5pt; margin:0 0 3pt 0; line-height:1.25;}
.job {font-size:10.5pt; font-weight:bold; color:#111111; margin:8pt 0 1pt 0;}
.meta {font-size:8.5pt; color:#969696; margin:0 0 4pt 0;}
ul {margin:0 0 0 14pt; padding:0;}
li {font-size:9pt; margin:0 0 2pt 0; line-height:1.25;}
.side p {font-size:9pt; margin:0 0 3pt 0;}
.small {font-size:8.5pt;}
.edu {font-size:8.5pt; font-weight:bold; margin:0;}
.edum {font-size:8pt; margin:0 0 5pt 0;}
td {vertical-align:top;}
.lnk {color:#0563c1; text-decoration:underline;}
"""
CV="""
<table style="width:100%"><tr>
<td style="width:62%"><p class="name">Ethan Navarro</p><p class="sub">Technical Artist / Unity Developer</p></td>
<td><p class="contact">Aalborg, Denmark</p><p class="contact">+00 000 000 000</p><p class="mail">your.email@example.com</p><p class="contact">ethannavarro.site · github.com/LILQK</p></td>
</tr></table>
<table style="width:100%"><tr>
<td style="width:56%; padding-right:24pt">
<h2>PROFILE</h2>
<p>Technical Artist and Unity developer with 4+ years in a small production studio. I started at PRODUKTIA as a Technical Artist intern and became one of its main Unity developers, working between artists and engineers: HLSL and Shader Graph shaders, visual effects, 2D/3D animation, asset optimization pipelines and lighting. Most of what I shipped ran on hardware with tight budgets (standalone VR headsets, Android and iOS), where holding a stable frame rate is the core challenge.</p>
<h2>EXPERIENCE</h2>
<p class="job">PRODUKTIA - Unity Developer / Programmer</p>
<p class="meta">Barcelona, Spain | Jan 2023 - Jul 2026</p>
<ul>
<li>Wrote custom underwater shaders and narrative VFX for <i>Nanoscope</i> (Shader Graph), integrating optimized 3D assets at a stable frame rate on Meta Quest.</li>
<li>Optimized <i>GRAPAT de BTC</i>, a multiplayer VR escape room played by 200+ students, to a stable 90 FPS on Pico 4.</li>
<li>Ran a photogrammetry asset pipeline for <i>PompeuLab VR</i>: cleaned and optimized 3D-scanned environments in Blender for real-time use; led the team.</li>
<li>Shipped 15+ cross-platform Unity apps for Android, iOS and Meta Quest; profiled and optimized graphics performance on device.</li>
<li>Created 2D and 3D animation, motion graphics, VFX and lighting setups in Blender and After Effects; built Unreal Engine virtual sets.</li>
</ul>
<p class="job">PRODUKTIA - Technical Artist Intern</p>
<p class="meta">Barcelona, Spain | Sep 2022 - Dec 2022</p>
<ul><li>Converted and optimized CAD 3D models into real-time game assets.</li></ul>
<p class="job">AIAmigo.io - Co-Founder &amp; Full Stack Developer</p>
<p class="meta">Remote | Jun 2025 - Present</p>
<ul><li>Co-founded a B2B SaaS and browser extension; working remotely with Danish colleagues.</li></ul>
<p class="job">EMAiD - Game Development &amp; Programming Professor</p>
<p class="meta">Barcelona, Spain | Feb 2025 - Sep 2025</p>
<ul><li>Taught Unity and C# game programming to 30+ higher-education students.</li></ul>
<h2>SELECTED PROJECTS</h2>
<ul>
<li><b>Red Button</b> - solo Unity/C# mobile game on Google Play; 1,000+ downloads, 100+ monthly players.</li>
<li><b>Multi-IDE Support for Unity</b> - open-source Unity editor package (C#).</li>
<li><b>Game jams</b> - <i>Ship the Sheep</i> (2D Unity, Aseprite), Global Game Jam 2023, 2024, 2025.</li>
</ul>
</td>
<td>
<h2>TECH ART SKILLS</h2>
<p>Shaders: HLSL &amp; Shader Graph</p>
<p>Particles &amp; visual effects</p>
<p>Lighting &amp; post-processing</p>
<p>2D &amp; 3D animation</p>
<p>Asset pipelines &amp; optimization</p>
<p>Profiling on mobile &amp; VR hardware</p>
<p>Photogrammetry</p>
<p>Unity editor tooling (C#)</p>
<h2>ENGINES &amp; TOOLS</h2>
<p class="small">Unity, C#, HLSL, Shader Graph, Unreal Engine, Blender, After Effects, Aseprite, Premiere Pro, DaVinci Resolve</p>
<h2>PLATFORMS</h2>
<p class="small">Android, iOS, Meta Quest, Pico 4</p>
<h2>LANGUAGES</h2>
<p class="small">Spanish and Catalan: native</p>
<p class="small">English: upper-intermediate</p>
<h2>EDUCATION</h2>
<p class="edu">Bachelor's Degree in Digital Media Design</p><p class="edum">UOC | 2024 - Present</p>
<p class="edu">Postgraduate Diploma in Game Development</p><p class="edum">UOC | 2024</p>
<p class="edu">Advanced Vocational Diploma in Video Game Design and Development</p><p class="edum">EMAiD | 2022</p>
<p class="edu">Intermediate Vocational Diploma in Plastic Arts and Design</p><p class="edum">EMAiD | 2020</p>
</td></tr></table>
"""
LETTER="""
<table style="width:100%"><tr>
<td style="width:62%"><p class="name">Ethan Navarro</p><p class="sub">Technical Artist / Unity Developer</p></td>
<td><p class="contact">Aalborg, Denmark</p><p class="contact">+00 000 000 000</p><p class="mail">your.email@example.com</p></td>
</tr></table>
<h2>COVER LETTER - TECH ARTIST, 2D PROJECT (UNITY)</h2>
<p>Dear Pine Creek Games team,</p>
<p>I'm applying for the Tech Artist contract on your 2D Unity project. For the past four years I've worked at PRODUKTIA, a small studio, where I started as a Technical Artist intern and became one of its main Unity developers. My job was to be the bridge between the artists and the code, and that's the role I'm looking for.</p>
<p><b>Shaders and VFX.</b> I write shaders in HLSL and Shader Graph. On <i>Nanoscope</i> I built the custom underwater shaders and narrative effects and kept them running on a standalone Quest headset without losing visual quality.</p>
<p><b>Optimization on limited hardware.</b> Almost everything I shipped ran on mobile chipsets: Android and iOS apps, Meta Quest and Pico 4. VR headsets are some of the hardest targets to optimize for: frame-rate drops are immediately noticeable, and the budgets for draw calls, overdraw and memory are tight. I got a multiplayer VR escape room to a locked 90 FPS on Pico 4 and profiled graphics bottlenecks across 15+ releases. I haven't shipped on Nintendo Switch yet, but its constraints are close to the ones I deal with every day.</p>
<p><b>Animation and pipelines.</b> I've made 2D and 3D animation in Blender and After Effects. I've also moved CAD models and photogrammetry scans into Unity with polygon and texture budgets in mind, and built Unity editor tooling in C#. Toon Boom would be new to me, but I learn new tools quickly and I'd enjoy getting your Toon Boom-to-Unity pipeline running smoothly.</p>
<p><b>Lighting and post-processing.</b> I've lit scenes in engine and for live video shoots, and did colour, VFX and compositing in post-production. That background gives me a good eye for colour grading and mood.</p>
<p>I live in Aalborg, so I'm in your time zone, and I can start immediately on a 4-5 month freelance contract. I'm used to remote work with daily syncs. You can see my work at ethannavarro.site.</p>
<p>Thank you for your time. I'd love to talk about how I can help your team.</p>
<p>Best regards,<br/>Ethan Navarro</p>
"""

def page(out,title,blocks):
    w=pymupdf.DocumentWriter(out); mb=pymupdf.paper_rect("a4"); dev=w.begin_page(mb)
    for html,rect in blocks:
        s=pymupdf.Story(html=html,user_css=CSS); more,_=s.place(pymupdf.Rect(rect)); s.draw(dev)
        if more: print("OVERFLOW",out,rect)
    w.end_page(); w.close()
    d=pymupdf.open(out); d.set_metadata({"title":title,"author":"Ethan Navarro"}); d.saveIncr()
    d[0].get_pixmap(dpi=80).save(out.replace(".pdf",".png")); print("ok",out)
C=['<p class="name">Ethan Navarro</p><p class="sub">Technical Artist / Unity Developer</p>', '<p class="contact">Aalborg, Denmark</p><p class="contact">+00 000 000 000</p><p class="mail">your.email@example.com</p><p class="contact"><span class=lnk>ethannavarro.site</span> · <span class=lnk>github.com/LILQK</span></p>', '\n<h2>PROFILE</h2>\n<p>Technical Artist and Unity developer with 4+ years in a small production studio. I started at PRODUKTIA as a Technical Artist intern and became one of its main Unity developers, working between artists and engineers: HLSL and Shader Graph shaders, visual effects, 2D/3D animation, asset optimization pipelines and lighting. Most of what I shipped ran on hardware with tight budgets (standalone VR headsets, Android and iOS), where holding a stable frame rate is the core challenge.</p>\n<h2>EXPERIENCE</h2>\n<p class="job">PRODUKTIA - Unity Developer / Programmer</p>\n<p class="meta">Barcelona, Spain | Jan 2023 - Jul 2026</p>\n<ul>\n<li>Wrote custom underwater shaders and narrative VFX for <i class=lnk>Nanoscope</i> (Shader Graph), integrating optimized 3D assets at a stable frame rate on Meta Quest.</li>\n<li>Optimized <i class=lnk>GRAPAT de BTC</i>, a multiplayer VR escape room played by 200+ students, to a stable 90 FPS on Pico 4.</li>\n<li>Ran a photogrammetry asset pipeline for <i class=lnk>PompeuLab VR</i>: cleaned and optimized 3D-scanned environments in Blender for real-time use; led the team.</li>\n<li>Shipped 15+ cross-platform Unity apps for Android, iOS and Meta Quest; profiled and optimized graphics performance on device.</li>\n<li>Created 2D and 3D animation, motion graphics, VFX and lighting setups in Blender and After Effects; built Unreal Engine virtual sets.</li>\n</ul>\n<p class="job">PRODUKTIA - Technical Artist Intern</p>\n<p class="meta">Barcelona, Spain | Sep 2022 - Dec 2022</p>\n<ul><li>Converted and optimized CAD 3D models into real-time game assets.</li></ul>\n<p class="job">AIAmigo.io - Co-Founder &amp; Full Stack Developer</p>\n<p class="meta">Remote | Jun 2025 - Present</p>\n<ul><li>Co-founded a B2B SaaS and browser extension; working remotely with Danish colleagues.</li></ul>\n<p class="job">EMAiD - Game Development &amp; Programming Professor</p>\n<p class="meta">Barcelona, Spain | Feb 2025 - Sep 2025</p>\n<ul><li>Taught Unity and C# game programming to 30+ higher-education students.</li></ul>\n<h2>SELECTED PROJECTS</h2>\n<ul>\n<li><b class=lnk>Red Button</b> - solo Unity/C# mobile game on Google Play; 1,000+ downloads, 100+ monthly players.</li>\n<li><b class=lnk>Multi-IDE Support for Unity</b> - open-source Unity editor package (C#).</li>\n<li><b>Game jams</b> - <i class=lnk>Ship the Sheep</i> (2D Unity, Aseprite), Global Game Jam 2023, 2024, 2025.</li>\n</ul>\n', '\n<h2>TECH ART SKILLS</h2>\n<p>Shaders: HLSL &amp; Shader Graph</p>\n<p>Particles &amp; visual effects</p>\n<p>Lighting &amp; post-processing</p>\n<p>2D &amp; 3D animation</p>\n<p>Asset pipelines &amp; optimization</p>\n<p>Profiling on mobile &amp; VR hardware</p>\n<p>Photogrammetry</p>\n<p>Unity editor tooling (C#)</p>\n<h2>ENGINES &amp; TOOLS</h2>\n<p class="small">Unity, C#, HLSL, Shader Graph, Unreal Engine, Blender, After Effects, Aseprite, Premiere Pro, DaVinci Resolve</p>\n<h2>PLATFORMS</h2>\n<p class="small">Android, iOS, Meta Quest, Pico 4</p>\n<h2>LANGUAGES</h2>\n<p class="small">Spanish and Catalan: native</p>\n<p class="small">English: upper-intermediate</p>\n<h2>EDUCATION</h2>\n<p class="edu">Bachelor\'s Degree in Digital Media Design</p><p class="edum">UOC | 2024 - Present</p>\n<p class="edu">Postgraduate Diploma in Game Development</p><p class="edum">UOC | 2024</p>\n<p class="edu">Advanced Vocational Diploma in Video Game Design and Development</p><p class="edum">EMAiD | 2022</p>\n<p class="edu">Intermediate Vocational Diploma in Plastic Arts and Design</p><p class="edum">EMAiD | 2020</p>\n']; L=['<p class="name">Ethan Navarro</p><p class="sub">Technical Artist / Unity Developer</p>', '<p class="contact">Aalborg, Denmark</p><p class="contact">+00 000 000 000</p><p class="mail">your.email@example.com</p>']; BL="<h2>COVER LETTER - TECH ARTIST, 2D PROJECT (UNITY)</h2>\n<p>Dear Pine Creek Games team,</p>\n<p>I'm applying for the Tech Artist contract on your 2D Unity project. For four years I worked at PRODUKTIA, a small studio, where I started as a Technical Artist intern and became one of its main Unity developers, acting as the bridge between artists and code.</p>\n<p><b>Shaders and VFX.</b> I write shaders in HLSL and Shader Graph. On <a style=\"color:#0563c1; text-decoration:underline\" href=\"https://www.youtube.com/watch?v=bA-adzFTysM\"><i>Nanoscope</i></a> I built custom underwater shaders and effects that ran smoothly on a standalone Quest headset.</p>\n<p><b>Optimization.</b> Most of what I shipped ran on limited hardware: Android, iOS, Meta Quest and Pico 4. VR is one of the toughest targets to optimize for, and I got <a style=\"color:#0563c1; text-decoration:underline\" href=\"https://www.youtube.com/watch?v=9nOSR8jWNtw\"><i>GRAPAT de BTC</i></a>, a multiplayer VR escape room, to a locked 90 FPS on Pico 4. I haven't shipped on Switch yet, but its constraints are close to the ones I deal with every day.</p>\n<p><b>Animation and pipelines.</b> I've made 2D and 3D animation in Blender and After Effects, and moved CAD and photogrammetry assets into Unity within polygon and texture budgets. Toon Boom would be new to me, but I learn tools quickly and would enjoy building your Toon Boom-to-Unity pipeline.</p>\n<p>I live in Aalborg, so I'm in your time zone. You can see my work at <a style=\"color:#0563c1; text-decoration:underline\" href=\"https://ethannavarro.site/\">ethannavarro.site</a>.</p>\n<p>Thank you for your time. I'd love to talk.</p>\n<p>Best regards,<br/>Ethan Navarro</p>"
page("Ethan_Navarro_PineCreek_TechArtist_CV.pdf","Ethan Navarro - Tech Artist CV",
 [(C[0],(40,32,360,90)),(C[1],(385,32,560,100)),(C[2],(40,92,365,815)),(C[3].replace('class="side"',''),(400,92,560,815))])
page("Ethan_Navarro_PineCreek_Cover_Letter.pdf","Ethan Navarro - Cover Letter",
 [(L[0],(40,32,360,90)),(L[1],(385,32,560,100)),(BL,(40,100,555,815))])

def add_links(path, pairs):
    d=pymupdf.open(path); p=d[0]
    for text,uri in pairs:
        for r in p.search_for(text)[:1]:
            p.insert_link({"kind":pymupdf.LINK_URI,"from":r,"uri":uri})
    d.saveIncr()
add_links("Ethan_Navarro_PineCreek_Cover_Letter.pdf",[("Nanoscope","https://www.youtube.com/watch?v=bA-adzFTysM"),("GRAPAT de BTC","https://www.youtube.com/watch?v=9nOSR8jWNtw"),("ethannavarro.site.","https://ethannavarro.site/"),("your.email@example.com","mailto:your.email@example.com")])

add_links("Ethan_Navarro_PineCreek_TechArtist_CV.pdf",[("Nanoscope","https://www.youtube.com/watch?v=bA-adzFTysM"),("GRAPAT de BTC","https://www.youtube.com/watch?v=9nOSR8jWNtw"),("PompeuLab VR","https://www.youtube.com/watch?v=RcC_8GEjm5M"),("Red Button","https://ethannavarro.site/projects/red-button"),("Multi-IDE Support for Unity","https://ethannavarro.site/projects/unity-multi-ide-support"),("Ship the Sheep","https://ethannavarro.site/projects/ship-the-sheep"),("your.email@example.com","mailto:your.email@example.com"),("ethannavarro.site","https://ethannavarro.site/"),("github.com/LILQK","https://github.com/LILQK")])
