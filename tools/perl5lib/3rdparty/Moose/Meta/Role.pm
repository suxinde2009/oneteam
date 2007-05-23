#line 1 "Moose/Meta/Role.pm"

package Moose::Meta::Role;

use strict;
use warnings;
use metaclass;

use Carp         'confess';
use Scalar::Util 'blessed';
use B            'svref_2object';

our $VERSION   = '0.07';
our $AUTHORITY = 'cpan:STEVAN';

use Moose::Meta::Class;
use Moose::Meta::Role::Method;

use base 'Class::MOP::Module';

## Attributes

## roles

__PACKAGE__->meta->add_attribute('roles' => (
    reader  => 'get_roles',
    default => sub { [] }
));

## excluded roles

__PACKAGE__->meta->add_attribute('excluded_roles_map' => (
    reader  => 'get_excluded_roles_map',
    default => sub { {} }
));

## attributes

__PACKAGE__->meta->add_attribute('attribute_map' => (
    reader   => 'get_attribute_map',
    default  => sub { {} }
));

## required methods

__PACKAGE__->meta->add_attribute('required_methods' => (
    reader  => 'get_required_methods_map',
    default => sub { {} }
));

## method modifiers

__PACKAGE__->meta->add_attribute('before_method_modifiers' => (
    reader  => 'get_before_method_modifiers_map',
    default => sub { {} } # (<name> => [ (CODE) ])
));

__PACKAGE__->meta->add_attribute('after_method_modifiers' => (
    reader  => 'get_after_method_modifiers_map',
    default => sub { {} } # (<name> => [ (CODE) ])
));

__PACKAGE__->meta->add_attribute('around_method_modifiers' => (
    reader  => 'get_around_method_modifiers_map',
    default => sub { {} } # (<name> => [ (CODE) ])
));

__PACKAGE__->meta->add_attribute('override_method_modifiers' => (
    reader  => 'get_override_method_modifiers_map',
    default => sub { {} } # (<name> => CODE) 
));

## Methods 

sub method_metaclass { 'Moose::Meta::Role::Method' }

## subroles

sub add_role {
    my ($self, $role) = @_;
    (blessed($role) && $role->isa('Moose::Meta::Role'))
        || confess "Roles must be instances of Moose::Meta::Role";
    push @{$self->get_roles} => $role;
}

sub calculate_all_roles {
    my $self = shift;
    my %seen;
    grep { !$seen{$_->name}++ } $self, map { $_->calculate_all_roles } @{ $self->get_roles };
}

sub does_role {
    my ($self, $role_name) = @_;
    (defined $role_name)
        || confess "You must supply a role name to look for";
    # if we are it,.. then return true
    return 1 if $role_name eq $self->name;
    # otherwise.. check our children
    foreach my $role (@{$self->get_roles}) {
        return 1 if $role->does_role($role_name);
    }
    return 0;
}

## excluded roles

sub add_excluded_roles {
    my ($self, @excluded_role_names) = @_;
    $self->get_excluded_roles_map->{$_} = undef foreach @excluded_role_names;
}

sub get_excluded_roles_list {
    my ($self) = @_;
    keys %{$self->get_excluded_roles_map};
}

sub excludes_role {
    my ($self, $role_name) = @_;
    exists $self->get_excluded_roles_map->{$role_name} ? 1 : 0;
}

## required methods

sub add_required_methods {
    my ($self, @methods) = @_;
    $self->get_required_methods_map->{$_} = undef foreach @methods;
}

sub remove_required_methods {
    my ($self, @methods) = @_;
    delete $self->get_required_methods_map->{$_} foreach @methods;
}

sub get_required_method_list {
    my ($self) = @_;
    keys %{$self->get_required_methods_map};
}

sub requires_method {
    my ($self, $method_name) = @_;
    exists $self->get_required_methods_map->{$method_name} ? 1 : 0;
}

sub _clean_up_required_methods {
    my $self = shift;
    foreach my $method ($self->get_required_method_list) {
        $self->remove_required_methods($method)
            if $self->has_method($method);
    } 
}

## methods

# FIXME:
# this is an UGLY hack
sub get_method_map {    
    my $self = shift;
    $self->{'%!methods'} ||= {}; 
    $self->Moose::Meta::Class::get_method_map() 
}

# FIXME:
# Yes, this is a really really UGLY hack
# but it works, and until I can figure 
# out a better way, this is gonna be it. 

sub get_method          { (shift)->Moose::Meta::Class::get_method(@_)          }
sub has_method          { (shift)->Moose::Meta::Class::has_method(@_)          }
sub alias_method        { (shift)->Moose::Meta::Class::alias_method(@_)        }
sub get_method_list     { 
    grep {
        !/^meta$/
    } (shift)->Moose::Meta::Class::get_method_list(@_)     
}

sub find_method_by_name { (shift)->has_method(@_) }

# ... however the items in statis (attributes & method modifiers)
# can be removed and added to through this API

# attributes

sub add_attribute {
    my $self = shift;
    my $name = shift;
    my $attr_desc;
    if (scalar @_ == 1 && ref($_[0]) eq 'HASH') {
        $attr_desc = $_[0];
    }
    else {
        $attr_desc = { @_ };
    }
    $self->get_attribute_map->{$name} = $attr_desc;
}

sub has_attribute {
    my ($self, $name) = @_;
    exists $self->get_attribute_map->{$name} ? 1 : 0;
}

sub get_attribute {
    my ($self, $name) = @_;
    $self->get_attribute_map->{$name}
}

sub remove_attribute {
    my ($self, $name) = @_;
    delete $self->get_attribute_map->{$name}
}

sub get_attribute_list {
    my ($self) = @_;
    keys %{$self->get_attribute_map};
}

# method modifiers

# mimic the metaclass API
sub add_before_method_modifier { (shift)->_add_method_modifier('before', @_) }
sub add_around_method_modifier { (shift)->_add_method_modifier('around', @_) }
sub add_after_method_modifier  { (shift)->_add_method_modifier('after',  @_) }

sub _add_method_modifier {
    my ($self, $modifier_type, $method_name, $method) = @_;
    my $accessor = "get_${modifier_type}_method_modifiers_map";
    $self->$accessor->{$method_name} = [] 
        unless exists $self->$accessor->{$method_name};
    my $modifiers = $self->$accessor->{$method_name};
    # NOTE:
    # check to see that we aren't adding the 
    # same code twice. We err in favor of the 
    # first on here, this may not be as expected
    foreach my $modifier (@{$modifiers}) {
        return if $modifier == $method;
    }
    push @{$modifiers} => $method;
}

sub add_override_method_modifier {
    my ($self, $method_name, $method) = @_;
    (!$self->has_method($method_name))
        || confess "Cannot add an override of method '$method_name' " . 
                   "because there is a local version of '$method_name'";
    $self->get_override_method_modifiers_map->{$method_name} = $method;    
}

sub has_before_method_modifiers { (shift)->_has_method_modifiers('before', @_) }
sub has_around_method_modifiers { (shift)->_has_method_modifiers('around', @_) }
sub has_after_method_modifiers  { (shift)->_has_method_modifiers('after',  @_) }

# override just checks for one,.. 
# but we can still re-use stuff
sub has_override_method_modifier { (shift)->_has_method_modifiers('override',  @_) }

sub _has_method_modifiers {
    my ($self, $modifier_type, $method_name) = @_;
    my $accessor = "get_${modifier_type}_method_modifiers_map";   
    # NOTE:
    # for now we assume that if it exists,.. 
    # it has at least one modifier in it
    (exists $self->$accessor->{$method_name}) ? 1 : 0;
}

sub get_before_method_modifiers { (shift)->_get_method_modifiers('before', @_) }
sub get_around_method_modifiers { (shift)->_get_method_modifiers('around', @_) }
sub get_after_method_modifiers  { (shift)->_get_method_modifiers('after',  @_) }

sub _get_method_modifiers {
    my ($self, $modifier_type, $method_name) = @_;
    my $accessor = "get_${modifier_type}_method_modifiers_map";
    @{$self->$accessor->{$method_name}};
}

sub get_override_method_modifier {
    my ($self, $method_name) = @_;
    $self->get_override_method_modifiers_map->{$method_name};    
}

sub get_method_modifier_list {
    my ($self, $modifier_type) = @_;
    my $accessor = "get_${modifier_type}_method_modifiers_map";    
    keys %{$self->$accessor};
}

## applying a role to a class ...

sub _check_excluded_roles {
    my ($self, $other) = @_;
    if ($other->excludes_role($self->name)) {
        confess "Conflict detected: " . $other->name . " excludes role '" . $self->name . "'";
    }
    foreach my $excluded_role_name ($self->get_excluded_roles_list) {
        if ($other->does_role($excluded_role_name)) { 
            confess "The class " . $other->name . " does the excluded role '$excluded_role_name'";
        }
        else {
            if ($other->isa('Moose::Meta::Role')) {
                $other->add_excluded_roles($excluded_role_name);
            }
            # else -> ignore it :) 
        }
    }    
}

sub _check_required_methods {
    my ($self, $other) = @_;
    # NOTE:
    # we might need to move this down below the 
    # the attributes so that we can require any 
    # attribute accessors. However I am thinking 
    # that maybe those are somehow exempt from 
    # the require methods stuff.  
    foreach my $required_method_name ($self->get_required_method_list) {
        
        unless ($other->find_method_by_name($required_method_name)) {
            if ($other->isa('Moose::Meta::Role')) {
                $other->add_required_methods($required_method_name);
            }
            else {
                confess "'" . $self->name . "' requires the method '$required_method_name' " . 
                        "to be implemented by '" . $other->name . "'";
            }
        }
        else {
            # NOTE:
            # we need to make sure that the method is 
            # not a method modifier, because those do 
            # not satisfy the requirements ...
            my $method = $other->get_method($required_method_name);
            # check if it is an override or a generated accessor ..
            (!$method->isa('Moose::Meta::Method::Overriden') &&
             !$method->isa('Class::MOP::Method::Accessor'))
                || confess "'" . $self->name . "' requires the method '$required_method_name' " . 
                           "to be implemented by '" . $other->name . "', the method is only a method modifier";
            # before/after/around methods are a little trickier
            # since we wrap the original local method (if applicable)
            # so we need to check if the original wrapped method is 
            # from the same package, and not a wrap of the super method 
            if ($method->isa('Class::MOP::Method::Wrapped')) {
                ($method->get_original_method->package_name eq $other->name)
                    || confess "'" . $self->name . "' requires the method '$required_method_name' " . 
                               "to be implemented by '" . $other->name . "', the method is only a method modifier";            
            }
        }        
    }    
}

sub _apply_attributes {
    my ($self, $other) = @_;    
    foreach my $attribute_name ($self->get_attribute_list) {
        # it if it has one already
        if ($other->has_attribute($attribute_name) &&
            # make sure we haven't seen this one already too
            $other->get_attribute($attribute_name) != $self->get_attribute($attribute_name)) {
            # see if we are being composed  
            # into a role or not
            if ($other->isa('Moose::Meta::Role')) {                
                # all attribute conflicts between roles 
                # result in an immediate fatal error 
                confess "Role '" . $self->name . "' has encountered an attribute conflict " . 
                        "during composition. This is fatal error and cannot be disambiguated.";
            }
            else {
                # but if this is a class, we 
                # can safely skip adding the 
                # attribute to the class
                next;
            }
        }
        else {
            # NOTE:
            # this is kinda ugly ...
            if ($other->isa('Moose::Meta::Class')) { 
                $other->_process_attribute(
                    $attribute_name,
                    %{$self->get_attribute($attribute_name)}
                );             
            }
            else {
                $other->add_attribute(
                    $attribute_name,
                    $self->get_attribute($attribute_name)
                );                
            }
        }
    }    
}

sub _apply_methods {
    my ($self, $other) = @_;   
    foreach my $method_name ($self->get_method_list) {
        # it if it has one already
        if ($other->has_method($method_name) &&
            # and if they are not the same thing ...
            $other->get_method($method_name)->body != $self->get_method($method_name)->body) {
            # see if we are composing into a role
            if ($other->isa('Moose::Meta::Role')) { 
                # method conflicts between roles result 
                # in the method becoming a requirement
                $other->add_required_methods($method_name);
                # NOTE:
                # we have to remove the method from our 
                # role, if this is being called from combine()
                # which means the meta is an anon class
                # this *may* cause problems later, but it 
                # is probably fairly safe to assume that 
                # anon classes will only be used internally
                # or by people who know what they are doing
                $other->Moose::Meta::Class::remove_method($method_name)
                    if $other->name =~ /__COMPOSITE_ROLE_SANDBOX__/;
            }
            else {
                next;
            }
        }
        else {
            # add it, although it could be overriden 
            $other->alias_method(
                $method_name,
                $self->get_method($method_name)
            );
        }
    }     
}

sub _apply_override_method_modifiers {
    my ($self, $other) = @_;    
    foreach my $method_name ($self->get_method_modifier_list('override')) {
        # it if it has one already then ...
        if ($other->has_method($method_name)) {
            # if it is being composed into another role
            # we have a conflict here, because you cannot 
            # combine an overriden method with a locally
            # defined one 
            if ($other->isa('Moose::Meta::Role')) { 
                confess "Role '" . $self->name . "' has encountered an 'override' method conflict " . 
                        "during composition (A local method of the same name as been found). This " . 
                        "is fatal error.";
            }
            else {
                # if it is a class, then we 
                # just ignore this here ...
                next;
            }
        }
        else {
            # if no local method is found, then we 
            # must check if we are a role or class
            if ($other->isa('Moose::Meta::Role')) { 
                # if we are a role, we need to make sure 
                # we dont have a conflict with the role 
                # we are composing into
                if ($other->has_override_method_modifier($method_name) &&
                    $other->get_override_method_modifier($method_name) != $self->get_override_method_modifier($method_name)) {
                    confess "Role '" . $self->name . "' has encountered an 'override' method conflict " . 
                            "during composition (Two 'override' methods of the same name encountered). " . 
                            "This is fatal error.";
                }
                else {   
                    # if there is no conflict,
                    # just add it to the role  
                    $other->add_override_method_modifier(
                        $method_name, 
                        $self->get_override_method_modifier($method_name)
                    );                    
                }
            }
            else {
                # if this is not a role, then we need to 
                # find the original package of the method
                # so that we can tell the class were to 
                # find the right super() method
                my $method = $self->get_override_method_modifier($method_name);
                my $package = svref_2object($method)->GV->STASH->NAME;
                # if it is a class, we just add it
                $other->add_override_method_modifier($method_name, $method, $package);
            }
        }
    }    
}

sub _apply_method_modifiers {
    my ($self, $modifier_type, $other) = @_;    
    my $add = "add_${modifier_type}_method_modifier";
    my $get = "get_${modifier_type}_method_modifiers";    
    foreach my $method_name ($self->get_method_modifier_list($modifier_type)) {
        $other->$add(
            $method_name,
            $_
        ) foreach $self->$get($method_name);
    }    
}

sub _apply_before_method_modifiers { (shift)->_apply_method_modifiers('before' => @_) }
sub _apply_around_method_modifiers { (shift)->_apply_method_modifiers('around' => @_) }
sub _apply_after_method_modifiers  { (shift)->_apply_method_modifiers('after'  => @_) }

my $anon_counter = 0;

sub apply {
    my ($self, $other) = @_;
    
    unless ($other->isa('Moose::Meta::Class') || $other->isa('Moose::Meta::Role')) {
    
        # Runtime Role mixins
            
        # FIXME:
        # We really should do this better, and 
        # cache the results of our efforts so 
        # that we don't need to repeat them.
        
        my $pkg_name = __PACKAGE__ . "::__RUNTIME_ROLE_ANON_CLASS__::" . $anon_counter++;
        eval "package " . $pkg_name . "; our \$VERSION = '0.00';";
        die $@ if $@;

        my $object = $other;

        $other = Moose::Meta::Class->initialize($pkg_name);
        $other->superclasses(blessed($object));     
        
        bless $object => $pkg_name;
    }
    
    $self->_check_excluded_roles($other);
    $self->_check_required_methods($other);  

    $self->_apply_attributes($other);         
    $self->_apply_methods($other);   

    $self->_apply_override_method_modifiers($other);                  
    $self->_apply_before_method_modifiers($other);                  
    $self->_apply_around_method_modifiers($other);                  
    $self->_apply_after_method_modifiers($other);          

    $other->add_role($self);
}

sub combine {
    my ($class, @roles) = @_;
    
    my $pkg_name = __PACKAGE__ . "::__COMPOSITE_ROLE_SANDBOX__::" . $anon_counter++;
    eval "package " . $pkg_name . "; our \$VERSION = '0.00';";
    die $@ if $@;
    
    my $combined = $class->initialize($pkg_name);
    
    foreach my $role (@roles) {
        $role->apply($combined);
    }
    
    $combined->_clean_up_required_methods;   
    
    return $combined;
}

1;

__END__

#line 738