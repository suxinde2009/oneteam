function DiscoCacheEntry(jid, node, isCapsNode)
{
    if (isCapsNode) {
        if (this.capsCache[node])
            return this.capsCache[node];
        this.capsCache[node] = this;
    } else {
        var id = jid + (node ? "#"+node : "");
        if (this.cache[id])
            return this.cache[id];
        this.cache[id] = this;
    }

    this.jid = jid;
    this.node = node;
    this._isCapsNode = isCapsNode;

    return this;
}


_DECL_(DiscoCacheEntry).prototype =
{
    cache: {},
    capsCache: {},

    requestDiscoInfo: function(featureName, forceUpdate, callback)
    {
        if (!this.discoInfo)
            if (this.capsNode) {
                this._populateDiscoInfoFromCaps(featureName, callback);
                if (!this.discoInfo)
                    return null;
            } else if (this._isCapsNode)
                this._populateDiscoInfoFromCapsCache();

        if (!callback)
            return this._feature(featureName);

        if (!this.discoInfo || (!this.capsNode && !this._isCapsNode && forceUpdate)) {
            if (!this.discoInfoCallbacks) {
                var iq = new JSJaCIQ();
                iq.setIQ(this.jid, null, "get");
                iq.setQuery("http://jabber.org/protocol/disco#info");
                if (this.node)
                    iq.getQuery().setAttribute("node", this.node);
                con.send(iq, function(pkt, _this) { _this._gotDiscoInfo(pkt) }, this);
                this.discoInfoCallbacks = [[featureName, callback]];
            } else
                this.discoInfoCallbacks.push([featureName, callback]);
            return null;
        }
        callback(this._feature(featureName), this);

        return this._feature(featureName);
    },

    requestDiscoItems: function(forceUpdate, callback)
    {
        if (!callback)
            return this.discoItems;

        if (!this.discoItems || forceUpdate) {
            if (!this.discoItemsCallbacks) {
                var iq = new JSJaCIQ();
                iq.setIQ(this.jid, null, "get");
                iq.setQuery("http://jabber.org/protocol/disco#items");
                if (this.node)
                    iq.getQuery().setAttribute("node", this.node);
                con.send(iq, function(pkt, _this) { _this._gotDiscoItems(pkt) }, this);
                this.discoItemsCallbacks = [callback];
            } else
                this.discoItemsCallbacks.push(callback);
            return null;
        }
        callback(this.discoItems, this);

        return this.discoItems;
    },

    updateCapsInfo: function(caps)
    {
        var [node, ver, ext] = [this.capsNode, this.capsVer, this.capsExt];

        this.capsNode = caps.getAttribute("node");
        this.capsVer = caps.getAttribute("ver");
        this.capsExt = (caps.getAttribute("ext") || "").split(/\s+/);

        if (node != this.capsNode || ver != this.capsVer ||
            ext.sort().join(" ") != this.capsExt.sort().join(" "))
            this.discoInfo = null;
    },

    destroy: function()
    {
        if (!this._isCapsNode)
            delete this.cache[this.jid + (this.node ? "" : "#"+this.node)];
    },

    _feature: function(featureName)
    {
        if (featureName == null)
            return this.discoInfo;
        if (featureName == "")
            return this.discoInfo.identity;
        return featureName in this.discoInfo.features;
    },

    _populateDiscoInfoFromCaps: function(featureName, callback)
    {
        var nodes = [this.capsVer].concat(this.capsExt);
        var infos = [];
        var capsCallback, capsCallbackData;

        for (var i = 0; i < nodes.length; i++) {
            var ce = new DiscoCacheEntry(this.jid, this.capsNode+"#"+nodes[i],
                                         true);
            var info = ce.requestDiscoInfo();
            if (info) {
                if (infos.length == i)
                    infos.push(info);
            } else if (callback) {
                if (!capsCallback)
                    capsCallback = new Callback(this._gotCapsInfo, this).
                        addArgs(capsCallbackData = {}, featureName, callback);
                capsCallbackData[this.capsNode+"#"+nodes[i]] = 1;
                ce.requestDiscoInfo(null, false, capsCallback);
            }
        }

        if (infos.length == nodes.length) {
            this.discoInfo = {
                identity: infos[0].identity,
                features: {}
            }
            for (var i = 0; i < infos.length; i++)
                for (var j in infos[i].features)
                    this.discoInfo.features[j] = 1
        }
    },

    _populateDiscoInfoFromCapsCache: function()
    {
        var s = account.cache.getValue("caps-"+this.node);

        if (s == null)
            return;

        s = s.split("\n");
        this.discoInfo = { features: {} };
        account.cache.bumpExpirationDate("caps-"+this.node,
                                         new Date(Date.now()+30*24*60*60*1000));

        if (s[0] || s[1] || s[2])
            this.discoInfo.identity = {
                name: s[0],
                type: s[1],
                category: s[2]
            }

        for (var i = 3; i < s.length; i++)
            this.discoInfo.features[s[i]] = 1;
    },

    _gotDiscoInfo: function(pkt)
    {
        var features = pkt.getQuery().getElementsByTagName("feature");
        var identity = pkt.getQuery().getElementsByTagName("identity")[0];

        this.discoInfo = { features: {} };

        if (identity)
            this.discoInfo.identity = {
                name: identity.getAttribute("name"),
                type: identity.getAttribute("type"),
                category: identity.getAttribute("category")
            };

        var vals = []
        for (var i = 0; i < features.length; i++)
            this.discoInfo.features[vals[i] = features[i].getAttribute("var")] = 1;

        for (i = 0; i < this.discoInfoCallbacks.length; i++) {
            var [featureName, callback] = this.discoInfoCallbacks[i];
            callback(this._feature(featureName), this);
        }

        if (this._isCapsNode) {
            with (this.discoInfo.identity||{name:"", type:"", category:""})
                vals.unshift(name||"", type||"", category||"");
            account.cache.setValue("caps-"+this.node, vals.join("\n"),
                                   new Date(Date.now()+30*24*60*60*1000));
        }

        delete this.discoInfoCallbacks;
    },

    _gotDiscoItems: function(pkt)
    {
        var items = pkt.getQuery().
            getElementsByTagNameNS("http://jabber.org/protocol/disco#items", "item");

        this.discoItems = [];
        for (var i = 0; i < items.length; i++)
            this.discoItems.push(new DiscoItem(items[i].getAttribute("jid"),
                                               items[i].getAttribute("name"),
                                               items[i].getAttribute("node")));

        for (var i = 0; i < this.discoItemsCallbacks.length; i++)
            this.discoItemsCallbacks[i].call(null, this.discoItems, this);

        delete this.discoItemsCallbacks;
    },

    _gotCapsInfo: function(info, item, nodes, featureName, callback)
    {
        delete nodes[item.node];
        if (nodes.__count__ != 0)
            return;

        this._populateDiscoInfoFromCaps();
        callback(this._feature(featureName), this);
    }
}

function DiscoItem(jid, name, node)
{
    this.discoJID = jid;
    this.discoName = name;
    this.discoNode = node;
}

_DECL_(DiscoItem).prototype =
{
    get _discoCacheEntry()
    {
        return META.ACCESSORS.replace(this, "_discoCacheEntry",
            new DiscoCacheEntry(this.discoJID || this.jid, this.discoNode));
    },

    updateCapsInfo: function(node)
    {
        this._discoCacheEntry.updateCapsInfo(node);
    },

    hasDiscoFeature: function(name, forceUpdate, callback)
    {
        return this._discoCacheEntry.requestDiscoInfo(name, forceUpdate, callback);
    },

    getDiscoIdentity: function(forceUpdate, callback)
    {
        return this._discoCacheEntry.requestDiscoInfo("", forceUpdate, callback);
    },

    getDiscoInfo: function(forceUpdate, callback)
    {
        return this._discoCacheEntry.requestDiscoInfo(null, forceUpdate, callback);
    },

    getDiscoItems: function(forceUpdate, callback)
    {
        return this._discoCacheEntry.requestDiscoItems(forceUpdate, callback);
    },

    getDiscoItemsByCategory: function(category, type, forceUpdate, callback)
    {
        if (callback)
            this.getDiscoItems(forceUpdate, new Callback(this._gotDiscoItems, this).
                addArgs(category, type, forceUpdate, callback));

        if (!this.getDiscoItems())
            return [];

        var ret = [], items = this.getDiscoItems();
        for (var i = 0; i < items.length; i++) {
            var id = items[i].getDiscoIdentity();
            if (id && (category == null || id.category == category) &&
                    (type == null || id.type == type))
                ret.push(items[i]);
        }
        return ret;
    },

    _gotDiscoItems: function(items, category, type, forceUpdate, callback)
    {
        for (var i = 0; i < items.length; i++)
            items[i].getDiscoIdentity(forceUpdate, new Callback(this._gotDiscoIdentity, this).
                addArgs(category, type, callback, items[i]));
    },

    _gotDiscoIdentity: function(id, category, type, callback, item)
    {
        if (id && (category == null || id.category == category) && (type == null || id.type == type))
            callback.call(null, this.getDiscoItemsByCategory(category, type), item);
    }
}