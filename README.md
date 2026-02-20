# GEOPHYSIX
Liste de commandes écrit en Pascal (Turbo Pascal ou Free Pascal) pour la science de la géophysique

<h3>Liste des fichiers</h3>

Voici la liste des différents fichiers proposés dans Ecologix :

<table>
	<tr>
		<th>Nom</th>
		<th>Description</th>
	</tr>
	<tr>
		<td><b>ATTEN.PAS</b></td>
		<td>Cette commande permet de calculer l'atténuation d'une onde sismique en fonction de la distance.</td>
	</tr>
	<tr>
		<td><b>BOUGUER.PAS</b></td>
		<td>Cette commande permet de calculer l'anomalie de Bouguer.</td>
	</tr>
	<tr>
		<td><b>DARCY.PAS</b></td>
		<td>Cette commande permet de calculer le débit d'un fluide à travers un sol perméable selon la Loi de Darcy.</td>
	</tr>
	<tr>
		<td><b>DEEPTEMP.PAS</b></td>
		<td>Cette commande permet de calculer la température en fonction de la profondeur en utilisant un gradient constant (Gradiant Géothermique).</td>
	</tr>
	<tr>
		<td><b>MAGNETIC.PAS</b></td>
		<td>Cette commande permet de calculer l'inclinaison du champ magnétique terrestre en fonction des coordonnées.</td> 
	</tr>
	<tr>
		<td><b>RADIODAT.PAS</b></td>
		<td>Cette commande permet de calculer l'âge d''une roche par la loi de désintégration radioactive.</td>
	</tr>
	<tr>
		<td><b>SEISMIC.PAS</b></td>
		<td>Cette commande permet de calculer la vitesse des ondes P et S en fonction de la densité et des modules élastiques.</td>
	</tr>
</table>

<h2>Compilation</h2>
	
Les fichiers Pascal n'ont aucune dépendances, il suffit de télécharger le fichier désiré et de le compiler avec Free Pascal avec la syntaxe de commande  :

<pre><b>fpc</b> <i>LEFICHIER.PAS</i></pre>
	
Sinon, vous pouvez également le compiler avec le Turbo Pascal à l'aide de la syntaxe de commande suivante :	

<pre><b>tpc</b> <i>LEFICHIER.PAS</i></pre>
	
Par exemple, si vous voulez compiler BOUGUER.PAS, vous devrez tapez la commande suivante :

<pre><b>fpc</b> BOUGUER.PAS</pre>

<h2>Licence</h2>
<ul>
 <li>Le code source est publié sous la licence <a href="https://github.com/gladir/GEOPHYSIX/blob/main/LICENSE">MIT</a>.</li>
 <li>Le paquet original est publié sous la licence <a href="https://github.com/gladir/GEOPHYSIX/blob/main/LICENSE">MIT</a>.</li>
</ul>
